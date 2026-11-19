import SwiftUI

enum Metrics {
    static let cardRadius: CGFloat = 22
    static let innerRadius: CGFloat = 14
    static let spacing: CGFloat = 14
    static let gutter: CGFloat = 16
    /// Keeps single-column content from stretching across a very wide window.
    static let readableWidth: CGFloat = 620
}

extension Font {
    /// The display face for numbers and titles; scales with Dynamic Type.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, weight: weight)
    }
}

// MARK: - Background

/// The app canvas: one flat, quiet colour behind everything.
struct AppBackground: View {
    var body: some View {
        Color.appBackground.ignoresSafeArea()
    }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: shape)
            .overlay { shape.strokeBorder(Color.hairline, lineWidth: 1) }
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Small uppercase label that sits above a value or a group.
    func eyebrow() -> some View {
        font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Buttons

/// The one high-emphasis action on a screen: a full-width accent capsule.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(.headline))
            .foregroundStyle(Color.onBrand)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .background(Color.brand, in: Capsule())
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.pop, value: configuration.isPressed)
    }
}

/// A compact tinted capsule for secondary actions inside cards.
struct SoftButtonStyle: ButtonStyle {
    var tint: Color = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(tint.opacity(0.13), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.pop, value: configuration.isPressed)
    }
}

/// Plain content that dips slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.pop, value: configuration.isPressed)
    }
}

// MARK: - Screen scaffolding

/// A vertically scrolling page with the standard gutters. Put a `CardStack`
/// (or `SplitColumns`) inside.
struct CardScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Where a vertical fold crosses a view, in that view's own coordinates.
struct FoldPosition: Equatable {
    /// Horizontal extent of the fold; zero-width while the device is flat.
    var range: ClosedRange<CGFloat>
    /// Width of the view that was measured.
    var containerWidth: CGFloat

    /// The fold's centre as a fraction of the view's width.
    var fraction: CGFloat {
        containerWidth > 0 ? (range.lowerBound + range.upperBound) / 2 / containerWidth : 0.5
    }
}

extension View {
    /// Reports the vertical fold crossing this view, or `nil` on devices
    /// without one. The flat (inactive, zero-width) fold is included, so a
    /// layout can already be split in the right place before the device bends.
    func onFoldChange(_ action: @escaping (FoldPosition?) -> Void) -> some View {
        modifier(FoldReader(action: action))
    }
}

private struct FoldReader: ViewModifier {
    let action: (FoldPosition?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: FoldPosition?.self) { proxy in
                let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
                guard let frame = regions.map(\.frame).first(where: { $0.height > $0.width }),
                      frame.minX > 0, frame.maxX < proxy.size.width
                else { return nil }
                return FoldPosition(range: frame.minX...frame.maxX, containerWidth: proxy.size.width)
            } action: { newValue in
                action(newValue)
            }
        } else {
            content
        }
    }
}

/// Two panes side by side, with the gap between them placed exactly on the
/// fold of an iPhone Duo (and in the middle on anything else), so nothing
/// straddles the crease.
struct FoldSplit<Leading: View, Trailing: View>: View {
    /// Centre the panes vertically against each other instead of top-aligning.
    var centered = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var fold: FoldPosition?

    var body: some View {
        FoldSplitLayout(fold: fold?.range, spacing: Metrics.gutter * 2, centered: centered) {
            leading
            trailing
        }
        .onFoldChange { fold = $0 }
    }
}

/// Two columns of cards on a wide (regular) layout, one column otherwise.
struct SplitColumns<Leading: View, Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            FoldSplit {
                CardStack { leading }
            } trailing: {
                CardStack(startIndex: 1) { trailing }
            }
        } else {
            CardStack {
                leading
                trailing
            }
        }
    }
}

/// Lays out exactly two subviews side by side, splitting around `fold` when
/// it's known and into equal halves otherwise.
private struct FoldSplitLayout: Layout {
    var fold: ClosedRange<CGFloat>?
    var spacing: CGFloat
    var centered = false

    private func columns(in width: CGFloat) -> (first: CGFloat, secondX: CGFloat, second: CGFloat) {
        let minimum: CGFloat = 220
        if let fold {
            let first = fold.lowerBound - spacing / 2
            let secondX = fold.upperBound + spacing / 2
            let second = width - secondX
            if first >= minimum, second >= minimum {
                return (first, secondX, second)
            }
        }
        let half = max(0, (width - spacing) / 2)
        return (half, half + spacing, half)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        guard subviews.count == 2 else { return CGSize(width: width, height: 0) }
        let cols = columns(in: width)
        let first = subviews[0].sizeThatFits(ProposedViewSize(width: cols.first, height: nil))
        let second = subviews[1].sizeThatFits(ProposedViewSize(width: cols.second, height: nil))
        return CGSize(width: width, height: max(first.height, second.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let cols = columns(in: bounds.width)
        let y = centered ? bounds.midY : bounds.minY
        let anchor: UnitPoint = centered ? .leading : .topLeading
        subviews[0].place(at: CGPoint(x: bounds.minX, y: y), anchor: anchor,
                          proposal: ProposedViewSize(width: cols.first, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.minX + cols.secondX, y: y), anchor: anchor,
                          proposal: ProposedViewSize(width: cols.second, height: nil))
    }
}
