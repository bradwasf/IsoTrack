import SwiftUI

/// A quiet rounded square holding a tinted SF Symbol; the standard row icon.
struct IconBadge: View {
    let symbol: String
    var tint: Color = .brand
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The IsoTrack capsule mark: a two-tone pill on a flat tile.
struct CapsuleMark: View {
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                }
            HStack(spacing: 0) {
                Color.brand
                Color.primary.opacity(0.85)
            }
            .frame(width: size * 0.58, height: size * 0.26)
            .clipShape(Capsule())
            .rotationEffect(.degrees(-40))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A card header: eyebrow title on the left, optional accessory on the right.
struct CardHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).eyebrow()
            Spacer(minLength: 8)
            accessory
        }
    }
}

extension CardHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// One figure with a caption, used in the stats grid.
struct StatTile: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.display(.title2))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(Motion.spring, value: value)
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

/// An icon, a title and a detail line, with an optional trailing accessory.
struct InfoRow<Accessory: View>: View {
    let symbol: String
    var tint: Color = .brand
    let title: String
    var detail: String?
    var detailTint: Color?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(detailTint ?? .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
    }
}

extension InfoRow where Accessory == EmptyView {
    init(symbol: String, tint: Color = .brand, title: String, detail: String? = nil, detailTint: Color? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail, detailTint: detailTint) {
            EmptyView()
        }
    }
}

/// A − / + stepper with a large rounded value.
struct CountStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1
    var label: String

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text("\(value)")
                .font(.display(.title3))
                .monospacedDigit()
                .frame(minWidth: 44)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            button("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .background(Color.surfaceRaised, in: Capsule())
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
    }
}

/// A pill strength and a pill count, as edited in a dose form.
struct DoseAmount: Equatable {
    static let strengths: [Double] = [10, 20, 30, 40]

    var strength: Double = 40
    var isCustom = false
    var customMg: Double?
    var pillCount = 1

    init() {}

    init(mgPerPill: Double, pillCount: Int) {
        self.pillCount = max(1, pillCount)
        if Self.strengths.contains(mgPerPill) {
            strength = mgPerPill
        } else {
            isCustom = true
            customMg = mgPerPill
        }
    }

    var mgPerPill: Double { isCustom ? max(0, customMg ?? 0) : strength }
    var totalMg: Double { mgPerPill * Double(pillCount) }
    var isValid: Bool { mgPerPill > 0 }
}

/// Strength chips, a pill stepper and the running total: the body of every
/// "how much" form (logging a dose, planning a scheduled one).
struct DoseAmountPicker: View {
    @Binding var amount: DoseAmount
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pill strength")
                    .font(.subheadline.weight(.semibold))
                FlowLayout(spacing: 8) {
                    ForEach(DoseAmount.strengths, id: \.self) { mg in
                        ChoiceChip(title: "\(Int(mg)) mg", isSelected: !amount.isCustom && amount.strength == mg) {
                            amount.isCustom = false
                            customFocused = false
                            amount.strength = mg
                        }
                    }
                    ChoiceChip(title: "Other", isSelected: amount.isCustom) {
                        amount.isCustom = true
                        customFocused = true
                    }
                    .accessibilityIdentifier("custom-strength")
                }
                if amount.isCustom {
                    HStack {
                        TextField("mg per pill", value: $amount.customMg, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($customFocused)
                            .font(.display(.title3))
                        Text("mg")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            HStack {
                Text("Pills")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                CountStepper(value: $amount.pillCount, range: 1...20, label: "Number of pills")
            }

            Rectangle().fill(Color.hairline).frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(amount.isValid ? "\(CourseSnapshot.trimmed(amount.totalMg)) mg" : "—")
                    .font(.display(.title2))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: amount.totalMg))
                    .animation(Motion.spring, value: amount.totalMg)
            }
        }
        .animation(Motion.spring, value: amount.isCustom)
    }
}

/// A selectable capsule chip.
struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .foregroundStyle(isSelected ? Color.onBrand : Color.primary)
                .background {
                    if isSelected {
                        Capsule().fill(Color.brand)
                    } else {
                        Capsule().fill(Color.surfaceRaised)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .pulse(on: isSelected, amount: 1.08)
        .animation(Motion.spring, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A thin capsule progress bar that fills from empty when it appears.
struct MeterBar: View {
    var value: Double
    var tint: Color = .brand
    var height: CGFloat = 8

    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surfaceRaised)
                Capsule().fill(tint)
                    .frame(width: max(height, proxy.size.width * max(0, min(1, shown))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(Motion.fill.delay(0.25)) { shown = value }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(Motion.spring) { shown = newValue }
        }
    }
}

/// Wraps its children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, in: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, in: bounds.width)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, in maxWidth: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (origins, width, y + rowHeight)
    }
}

// MARK: - Date text

enum DateText {
    /// "Tue, Nov 17"
    static func short(_ day: String) -> String {
        Day.date(from: day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Nov 17" — adds the year only when the date is far enough away to be ambiguous.
    static func monthDay(_ day: String, relativeTo today: String = Day.today) -> String {
        let date = Day.date(from: day)
        if abs(Day.distance(from: today, to: day)) < 300 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Tuesday, November 17"
    static func long(_ day: String) -> String {
        Day.date(from: day).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "today", "tomorrow", "in 3 days", "yesterday", "5 days ago"
    static func relative(_ day: String, to today: String) -> String {
        let days = Day.distance(from: today, to: day)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case let d where d > 1: return "in \(d) days"
        default: return "\(-days) days ago"
        }
    }
}
