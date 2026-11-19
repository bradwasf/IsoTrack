import SwiftUI

/// Everything about one day's doses: what's logged, and a form to add more.
/// Opened from the Today card, the week strip, the calendar, and history.
struct DaySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var amount = DoseAmount()
    @State private var didLoadDefaults = false

    init(day: String) {
        _date = State(initialValue: Day.date(from: day))
    }

    private var day: String { Day.string(from: date) }

    var body: some View {
        let course = store.course
        let logged = course.entries(on: day)
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.spacing) {
                    datePicker
                        .riseIn(0, distance: 18)
                    if course.hasSchedule {
                        scheduleCard(course)
                            .riseIn(1, distance: 18)
                    }
                    if !logged.isEmpty {
                        loggedCard(logged, course: course)
                            .transition(.blurReplace)
                    }
                    formCard(hasLogged: !logged.isEmpty, hasSchedule: course.hasSchedule)
                        .riseIn(course.hasSchedule ? 2 : 1, distance: 18)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .frame(maxWidth: Metrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { Color.appBackground.ignoresSafeArea() }
            .navigationTitle(day == store.today ? "Today" : DateText.short(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .animation(Motion.spring, value: logged)
        }
        .presentationDetents([.large])
        .presentationSizing(.form)
        .onAppear(perform: loadDefaults)
    }

    private var datePicker: some View {
        DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
            Label("Date", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
        }
        .card(padding: 14)
    }

    /// The day's scheduled doses as tick boxes, so a past day can be filled
    /// in (or corrected) the same way as today.
    private func scheduleCard(_ course: CourseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "Scheduled") {
                Text("\(course.takenSlotCount(on: day)) of \(course.schedule.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            SlotChecklist(day: day)
        }
        .card()
    }

    private func loggedCard(_ entries: [DoseEntry], course: CourseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Logged") {
                Text("\(CourseSnapshot.trimmed(entries.reduce(0) { $0 + $1.totalMg })) mg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    IconBadge(symbol: "pills.fill", tint: .good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(CourseSnapshot.trimmed(entry.totalMg)) mg")
                            .font(.subheadline.weight(.semibold))
                        Text(detail(for: entry, course: course))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteEntry(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(Color.brand)
                    .accessibilityLabel("Delete \(CourseSnapshot.trimmed(entry.totalMg)) mg dose")
                }
            }
        }
        .card()
    }

    /// "First meal · 2 × 30 mg" for a scheduled dose, "2 × 30 mg" otherwise.
    private func detail(for entry: DoseEntry, course: CourseSnapshot) -> String {
        let dose = CourseSnapshot.doseLabel(mgPerPill: entry.mgPerPill, pillCount: entry.pillCount)
        guard let slot = course.slot(for: entry) else { return dose }
        return "\(slot.label) · \(dose)"
    }

    private func formCard(hasLogged: Bool, hasSchedule: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(hasSchedule ? "Add an extra dose" : hasLogged ? "Add another dose" : "Add a dose")

            DoseAmountPicker(amount: $amount)

            Button {
                store.addDose(day: day, mgPerPill: amount.mgPerPill, pillCount: amount.pillCount)
                dismiss()
            } label: {
                Label(amount.isValid ? "Add \(CourseSnapshot.trimmed(amount.totalMg)) mg" : "Add dose", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!amount.isValid)
            .accessibilityIdentifier("add-dose")
        }
        .card()
    }

    /// Start from the user's usual dose so the common case is one tap.
    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        let course = store.course
        guard !course.entries.isEmpty else { return }
        amount = DoseAmount(mgPerPill: course.usualDose.mgPerPill, pillCount: course.usualDose.pillCount)
    }
}
