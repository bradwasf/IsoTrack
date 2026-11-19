import SwiftUI

/// First run: a welcome screen with two paths, then a short setup form.
struct OnboardingView: View {
    enum Step: Equatable {
        case welcome
        /// `midCourse` adds the "taken so far" field.
        case setup(midCourse: Bool)
    }

    @State private var step: Step = .welcome

    var body: some View {
        ZStack {
            AppBackground()
            switch step {
            case .welcome:
                WelcomeView(
                    onFresh: { step = .setup(midCourse: false) },
                    onMidCourse: { step = .setup(midCourse: true) }
                )
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading))
                    .combined(with: .opacity))
            case .setup(let midCourse):
                SetupView(midCourse: midCourse) { step = .welcome }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.4), value: step)
    }
}

private struct WelcomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onFresh: () -> Void
    let onMidCourse: () -> Void

    var body: some View {
        if horizontalSizeClass == .regular {
            // Open on an iPhone Duo: the mark on one half, the choices on the
            // other, so nothing sits on the fold.
            FoldSplit(centered: true) {
                brand.frame(maxWidth: 380).frame(maxWidth: .infinity)
            } trailing: {
                actions.frame(maxWidth: 380).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Metrics.gutter)
            .frame(maxHeight: .infinity)
        } else {
            ViewThatFits(in: .vertical) {
                stacked(spacious: true)
                ScrollView { stacked(spacious: false) }
            }
        }
    }

    private func stacked(spacious: Bool) -> some View {
        VStack(spacing: 0) {
            if spacious { Spacer(minLength: 24) }
            brand.padding(.vertical, spacious ? 0 : 32)
            if spacious { Spacer(minLength: 24) }
            actions
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
    }

    private var brand: some View {
        VStack(spacing: 18) {
            CapsuleMark(size: 96)
                .floating()
                .riseIn(0)
            VStack(spacing: 8) {
                Text("IsoTrack")
                    .font(.system(size: 44, weight: .semibold))
                Text("Your isotretinoin course, from the first capsule to your cumulative goal.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .riseIn(1)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onFresh) {
                Text("Start a new course")
            }
            .buttonStyle(PrimaryButtonStyle())
            .riseIn(3)

            Button(action: onMidCourse) {
                Text("I'm already mid-course")
                    .font(.display(.headline))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(.primary)
            .riseIn(4)

            Text("Personal tracking only. Not medical advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .riseIn(5)
        }
    }
}

private struct SetupView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .localeDefault

    let midCourse: Bool
    let onBack: () -> Void

    @State private var weight: Double?
    @State private var priorMg: Double?
    @State private var goal: GoalChoice = .perKg(150)
    @State private var customGoalTotal: Double?

    private var weightKg: Double? {
        guard let weight, weight > 0 else { return nil }
        return weightUnit.kilograms(from: weight)
    }

    private var targetMg: Double? {
        switch goal {
        case .customTotal: return (customGoalTotal ?? 0) > 0 ? customGoalTotal : nil
        case .perKg(let value): return weightKg.map { $0 * value }
        }
    }

    private var isValid: Bool { weightKg != nil && targetMg != nil }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            Group {
                if horizontalSizeClass == .regular {
                    FoldSplit {
                        VStack(alignment: .leading, spacing: Metrics.spacing) {
                            intro
                            weightCard.riseIn(1)
                            if midCourse { priorCard.riseIn(2) }
                        }
                    } trailing: {
                        VStack(alignment: .leading, spacing: Metrics.spacing) {
                            goalCard.riseIn(3)
                            targetCard.riseIn(4)
                            finish
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: Metrics.spacing) {
                        intro
                        weightCard.riseIn(1)
                        if midCourse { priorCard.riseIn(2) }
                        goalCard.riseIn(3)
                        targetCard.riseIn(4)
                        finish
                    }
                    .frame(maxWidth: Metrics.readableWidth)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(Motion.spring, value: goal)
    }

    @ViewBuilder
    private var intro: some View {
        Button(action: onBack) {
            Label("Back", systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Color.surface, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 6) {
            Text(midCourse ? "Pick up where you are" : "Set up your course")
                .font(.display(.largeTitle))
            Text("Three quick details and you're tracking. You can change any of them later.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .riseIn(0)
    }

    @ViewBuilder
    private var finish: some View {
        Button {
            guard let weightKg else { return }
            switch goal {
            case .customTotal:
                store.completeOnboarding(weightKg: weightKg, priorMg: midCourse ? (priorMg ?? 0) : 0,
                                         goalMgKg: 150, goalTotalMg: customGoalTotal)
            case .perKg(let value):
                store.completeOnboarding(weightKg: weightKg, priorMg: midCourse ? (priorMg ?? 0) : 0,
                                         goalMgKg: value)
            }
        } label: {
            Text("Start tracking")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isValid)
        .animation(Motion.spring, value: isValid)
        .padding(.top, 4)
        .riseIn(5)

        Text("IsoTrack is for personal tracking and isn't medical advice. Always follow your dermatologist's dosing plan.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your weight")
                    .font(.display(.headline))
                Spacer()
                Picker("Unit", selection: $weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            field {
                TextField(weightUnit == .lb ? "e.g. 165" : "e.g. 75", value: $weight, format: .number)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("weight-field")
                Text(weightUnit.rawValue).foregroundStyle(.secondary)
            }
            Text("Cumulative goals are set per kilogram of body weight.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var priorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Taken so far")
                .font(.display(.headline))
            field {
                TextField("0", value: $priorMg, format: .number)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("prior-field")
                Text("mg").foregroundStyle(.secondary)
            }
            Text("Total milligrams before today. A quick way: daily dose × days taken, so 40 mg for 30 days is 1,200.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cumulative goal")
                .font(.display(.headline))
            FlowLayout(spacing: 8) {
                ForEach(GoalChoice.presets) { choice in
                    ChoiceChip(title: choice.title, isSelected: goal == choice) {
                        goal = choice
                    }
                }
            }
            if goal == .customTotal {
                field {
                    TextField("e.g. 15000", value: $customGoalTotal, format: .number)
                        .keyboardType(.numberPad)
                    Text("mg total").foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Text(goal == .customTotal
                 ? "Enter the total your dermatologist gave you."
                 : "In mg per kg. Use the number your dermatologist gave you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your target").eyebrow()
            if let targetMg {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingNumber(value: targetMg)
                        .font(.system(size: 40, weight: .semibold))
                        .animation(Motion.spring, value: targetMg)
                    Text("mg")
                        .font(.display(.title3))
                        .foregroundStyle(.secondary)
                }
                if let kg = weightKg {
                    Text("\(kg.formatted(.number.precision(.fractionLength(1)))) kg · \((targetMg / kg).formatted(.number.precision(.fractionLength(0)))) mg/kg")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(weightKg == nil ? "Enter your weight to see it" : "Enter your goal total to see it")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.brand.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.display(.title3, weight: .semibold))
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
    }
}
