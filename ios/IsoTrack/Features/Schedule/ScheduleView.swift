import SwiftUI

// MARK: - Tick boxes

/// A day's scheduled doses as a column of tick boxes. Used on the Today card
/// (for today) and in the day sheet (for any day).
struct SlotChecklist: View {
    @Environment(AppStore.self) private var store
    let day: String

    var body: some View {
        let course = store.course
        VStack(spacing: 0) {
            ForEach(Array(course.schedule.enumerated()), id: \.element.id) { index, slot in
                SlotCheckRow(slot: slot, entry: course.entry(for: slot, on: day), index: index) { taken in
                    store.setTaken(taken, slot: slot, day: day)
                }
            }
        }
    }
}

/// One scheduled dose: a check circle, what it's taken with, and how much.
/// The whole row is the tap target.
struct SlotCheckRow: View {
    let slot: DoseSlot
    /// The entry that ticked this dose off, when it's been taken.
    let entry: DoseEntry?
    let index: Int
    let toggle: (Bool) -> Void

    private var taken: Bool { entry != nil }
    // Once taken, show what was actually logged, even if the plan changed since.
    private var mgPerPill: Double { entry?.mgPerPill ?? slot.mgPerPill }
    private var pillCount: Int { entry?.pillCount ?? slot.pillCount }
    private var totalMg: Double { mgPerPill * Double(pillCount) }

    private var detail: String {
        let dose = CourseSnapshot.doseLabel(mgPerPill: mgPerPill, pillCount: pillCount)
        if taken { return "Taken · \(dose)" }
        if let time = slot.reminderTimeText { return "\(dose) · \(time)" }
        return dose
    }

    var body: some View {
        Button {
            toggle(!taken)
        } label: {
            HStack(spacing: 14) {
                CheckCircle(isOn: taken)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.label)
                        .font(.display(.headline))
                        .foregroundStyle(taken ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                Text("\(CourseSnapshot.trimmed(totalMg)) mg")
                    .font(.display(.headline))
                    .monospacedDigit()
                    .foregroundStyle(taken ? Color.brand : Color.primary)
            }
            .frame(minHeight: 54)
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.spring, value: taken)
        // Ticking on gets the app-wide "dose logged" haptic; ticking off, a light one.
        .sensoryFeedback(trigger: taken) { _, isTaken in isTaken ? nil : .selection }
        .accessibilityLabel("\(slot.label), \(CourseSnapshot.trimmed(totalMg)) milligrams")
        .accessibilityValue(taken ? "taken" : "not taken")
        .accessibilityHint(taken ? "Marks this dose as not taken" : "Marks this dose as taken")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("slot-\(index)")
    }
}

// MARK: - Schedule

/// The dose schedule: the list of doses taken each day. Pushed from Settings,
/// or shown in a sheet (`ScheduleSheet`) from the Today card.
struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: DoseSlot?
    @State private var showClearConfirm = false

    var body: some View {
        let schedule = store.schedule
        List {
            Section {
                ForEach(schedule) { slot in
                    Button {
                        editing = slot
                    } label: {
                        row(slot)
                    }
                    .buttonStyle(PressableStyle())
                }
                .onDelete { offsets in
                    offsets.map { schedule[$0] }.forEach(store.deleteSlot)
                }
                .onMove(perform: store.moveSlots)

                Button {
                    editing = newSlot()
                } label: {
                    Label(schedule.isEmpty ? "Add your first dose" : "Add another dose", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 38)
                }
                .accessibilityIdentifier("add-slot")
            } header: {
                Text("Each day")
            } footer: {
                Text(schedule.isEmpty
                     ? "Split your day into separate doses — say 60 mg with your first meal and 30 mg with your second. Each one gets its own tick box on the Today tab."
                     : "Tick each one off on the Today tab. Swipe to remove, hold and drag to reorder. Changing the schedule never alters doses you've already logged.")
            }
            .listRowBackground(Color.surface)

            if !schedule.isEmpty {
                Section {
                    LabeledContent("Daily total") {
                        Text("\(CourseSnapshot.trimmed(store.course.scheduledMg)) mg · \(store.course.scheduledPills) \(store.course.scheduledPills == 1 ? "pill" : "pills")")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Button("Stop using a schedule", role: .destructive) {
                        showClearConfirm = true
                    }
                } footer: {
                    Text("Without a schedule, Today goes back to one button that logs your usual dose.")
                }
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("Dose schedule")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Motion.spring, value: schedule)
        .sheet(item: $editing) { slot in
            SlotEditor(slot: slot)
        }
        .confirmationDialog("Remove every scheduled dose?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Remove schedule", role: .destructive) { store.clearSchedule() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Doses you've already logged stay in your history.")
        }
    }

    private func row(_ slot: DoseSlot) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: slot.reminderMinutes == nil ? "pills.fill" : "bell.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text([CourseSnapshot.doseLabel(mgPerPill: slot.mgPerPill, pillCount: slot.pillCount),
                      slot.reminderTimeText.map { "reminder at \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(CourseSnapshot.trimmed(slot.totalMg)) mg")
                .font(.display(.subheadline))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits this dose")
    }

    /// A sensible starting point: the next unused meal name, and the same
    /// pills as the previous dose (or the usual dose for the first one).
    private func newSlot() -> DoseSlot {
        let schedule = store.schedule
        let used = Set(schedule.map(\.label))
        let label = SlotEditor.mealLabels.first { !used.contains($0) } ?? "Dose \(schedule.count + 1)"
        let usual = store.course.usualDose
        return DoseSlot(id: UUID().uuidString, label: label,
                        mgPerPill: schedule.last?.mgPerPill ?? usual.mgPerPill,
                        pillCount: schedule.last?.pillCount ?? usual.pillCount,
                        reminderMinutes: nil)
    }
}

/// The schedule in its own sheet, for opening straight from the Today card.
struct ScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScheduleView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationSizing(.form)
    }
}

// MARK: - Editing one dose

/// Adds or edits one scheduled dose: what it's taken with, how much, and an
/// optional reminder time.
struct SlotEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    static let mealLabels = ["First meal", "Second meal", "Third meal"]
    private static let suggestions = mealLabels + ["Morning", "Evening", "Bedtime"]
    /// Default reminder times for the first, second and third dose of the day.
    private static let defaultMinutes = [8 * 60, 13 * 60, 19 * 60]

    let slot: DoseSlot

    @State private var label: String
    @State private var amount: DoseAmount
    @State private var remind: Bool
    @State private var time: Date
    @State private var notificationsDenied = false
    @FocusState private var labelFocused: Bool

    init(slot: DoseSlot) {
        self.slot = slot
        _label = State(initialValue: slot.label)
        _amount = State(initialValue: DoseAmount(mgPerPill: slot.mgPerPill, pillCount: slot.pillCount))
        _remind = State(initialValue: slot.reminderMinutes != nil)
        _time = State(initialValue: Self.date(minutes: slot.reminderMinutes ?? 9 * 60))
    }

    private var existingIndex: Int? { store.schedule.firstIndex { $0.id == slot.id } }
    private var isNew: Bool { existingIndex == nil }

    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { amount.isValid && !trimmedLabel.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.spacing) {
                    labelCard.riseIn(0, distance: 18)
                    doseCard.riseIn(1, distance: 18)
                    reminderCard.riseIn(2, distance: 18)
                    if !isNew {
                        Button("Remove from schedule", role: .destructive) {
                            store.deleteSlot(slot)
                            dismiss()
                        }
                        .buttonStyle(SoftButtonStyle(tint: .warn))
                        .padding(.top, 4)
                        .riseIn(3, distance: 18)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .frame(maxWidth: Metrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { Color.appBackground.ignoresSafeArea() }
            .navigationTitle(isNew ? "New dose" : "Edit dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .accessibilityIdentifier("save-slot")
                }
            }
            .animation(Motion.spring, value: remind)
        }
        .presentationDetents([.large])
        .presentationSizing(.form)
        .onAppear(perform: loadDefaultTime)
        .onChange(of: remind) { _, isOn in
            if isOn { requestNotifications() }
        }
        .alert("Notifications are off", isPresented: $notificationsDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn them on for IsoTrack in the Settings app under Notifications.")
        }
    }

    private var labelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Taken with")
            TextField("e.g. First meal", text: $label)
                .focused($labelFocused)
                .font(.display(.title3))
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
                .accessibilityIdentifier("slot-label")
            FlowLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    ChoiceChip(title: suggestion, isSelected: trimmedLabel == suggestion) {
                        label = suggestion
                        labelFocused = false
                    }
                }
            }
        }
        .card()
    }

    private var doseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader("Dose")
            DoseAmountPicker(amount: $amount)
        }
        .card()
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Reminder")
            Toggle(isOn: $remind) {
                Text("Remind me")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.brand)
            if remind {
                DatePicker(selection: $time, displayedComponents: .hourAndMinute) {
                    Text("Time")
                        .font(.subheadline.weight(.semibold))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Text("A notification at this time, with a one-tap button that ticks this dose off. It's skipped once the dose is logged.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    /// A dose without a reminder yet starts from a time that suits its place
    /// in the day, ready for when the toggle is switched on.
    private func loadDefaultTime() {
        guard slot.reminderMinutes == nil else { return }
        let index = existingIndex ?? store.schedule.count
        if Self.defaultMinutes.indices.contains(index) {
            time = Self.date(minutes: Self.defaultMinutes[index])
        }
    }

    private func requestNotifications() {
        // Demo and UI-test runs never touch system notifications.
        guard !LaunchMode.isUITest, !LaunchMode.isDemo else { return }
        ReminderManager.shared.requestAuthorization { granted in
            if !granted {
                remind = false
                notificationsDenied = true
            }
        }
    }

    private func save() {
        guard isValid else { return }
        var updated = slot
        updated.label = trimmedLabel
        updated.mgPerPill = amount.mgPerPill
        updated.pillCount = amount.pillCount
        if remind {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
            updated.reminderMinutes = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
        } else {
            updated.reminderMinutes = nil
        }
        store.saveSlot(updated)
        dismiss()
    }
}
