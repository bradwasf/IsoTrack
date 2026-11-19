import SwiftUI

/// Everything around the pills: monthly appointments, pill supply, and a
/// side-effect journal to bring to the dermatologist.
struct CareView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: AppointmentDraft?
    @State private var showSupply = false
    @State private var checkInDay: DaySelection?

    var body: some View {
        NavigationStack {
            CardScroll {
                SplitColumns {
                    AppointmentsCard { editor = $0 }
                } trailing: {
                    SupplyCard { showSupply = true }
                    CheckInCard { checkInDay = DaySelection(day: $0) }
                }
            }
            .tabScreen("Care")
            .sheet(item: $editor) { draft in
                AppointmentEditor(draft: draft)
            }
            .sheet(isPresented: $showSupply) {
                SupplyEditor()
            }
            .sheet(item: $checkInDay) { selection in
                CheckInSheet(day: selection.day)
            }
        }
    }
}

// MARK: - Appointments

/// What the appointment editor is creating or moving.
struct AppointmentDraft: Identifiable {
    let id = UUID()
    var kind: Appointment.Kind
    var day: String
    /// Non-nil when moving an existing appointment to a new date.
    var rescheduling: Appointment?
}

struct AppointmentsCard: View {
    @Environment(AppStore.self) private var store
    let edit: (AppointmentDraft) -> Void

    @State private var showDone = false

    var body: some View {
        let overdue = store.overdueAppointments
        let upcoming = store.upcomingAppointments
        let done = store.attendedAppointments
        // Kinds with nothing on the books get a prompt to schedule the next one.
        let unscheduled = Appointment.Kind.allCases.filter { kind in
            !(overdue + upcoming).contains { $0.kind == kind }
        }

        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Appointments") {
                Button {
                    edit(AppointmentDraft(kind: .bloodDraw, day: store.suggestedDay(for: .bloodDraw)))
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("Add appointment")
            }

            if !overdue.isEmpty {
                group("Needs attention", tint: .warn) {
                    ForEach(overdue) { appointment in
                        AppointmentRow(appointment: appointment, tint: .warn) {
                            edit(AppointmentDraft(kind: appointment.kind, day: store.today, rescheduling: appointment))
                        }
                    }
                }
            }

            if !upcoming.isEmpty {
                group("Coming up", tint: .info) {
                    ForEach(upcoming) { appointment in
                        AppointmentRow(appointment: appointment, tint: .info) {
                            edit(AppointmentDraft(kind: appointment.kind, day: appointment.day, rescheduling: appointment))
                        }
                    }
                }
            }

            ForEach(unscheduled) { kind in
                Button {
                    edit(AppointmentDraft(kind: kind, day: store.suggestedDay(for: kind)))
                } label: {
                    InfoRow(symbol: kind.symbol, tint: .secondary,
                            title: "No \(kind.title.lowercased()) scheduled",
                            detail: "Suggested: \(DateText.short(store.suggestedDay(for: kind)))") {
                        Text("Schedule")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brand)
                    }
                }
                .buttonStyle(PressableStyle())
            }

            if !done.isEmpty {
                Rectangle().fill(Color.hairline).frame(height: 1)
                DisclosureGroup(isExpanded: $showDone) {
                    VStack(spacing: 12) {
                        ForEach(done) { appointment in
                            AppointmentRow(appointment: appointment, tint: .good, onReschedule: nil)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Done · \(done.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .tint(.secondary)
            }

            Text("You'll get a nudge the morning after an appointment if it isn't checked off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
        .animation(Motion.spring, value: store.appointments)
        .animation(Motion.spring, value: showDone)
    }

    private func group<Rows: View>(_ title: String, tint: Color, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            rows()
        }
    }
}

/// One appointment with a check-off control; long-press for more.
struct AppointmentRow: View {
    @Environment(AppStore.self) private var store
    let appointment: Appointment
    let tint: Color
    let onReschedule: (() -> Void)?

    var body: some View {
        let overdue = !appointment.attended && appointment.day < store.today
        HStack(spacing: 12) {
            IconBadge(symbol: appointment.kind.symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.kind.title)
                    .font(.subheadline.weight(.semibold))
                Text(appointment.attended
                     ? DateText.short(appointment.day)
                     : "\(DateText.short(appointment.day)) · \(DateText.relative(appointment.day, to: store.today))")
                    .font(.caption)
                    .foregroundStyle(overdue ? Color.warn : Color.secondary)
            }
            Spacer(minLength: 4)

            if overdue, let onReschedule {
                Button("Move", action: onReschedule)
                    .buttonStyle(SoftButtonStyle(tint: .warn))
                    .accessibilityLabel("Reschedule \(appointment.kind.title)")
            }

            Button {
                store.setAttended(appointment, !appointment.attended)
            } label: {
                Image(systemName: appointment.attended ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(appointment.attended ? Color.good : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pulse(on: appointment.attended, amount: 1.25)
            .sensoryFeedback(.success, trigger: appointment.attended)
            .accessibilityLabel(appointment.attended ? "Mark \(appointment.kind.title) not done" : "Mark \(appointment.kind.title) done")
        }
        .transition(.blurReplace)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                store.setAttended(appointment, !appointment.attended)
            } label: {
                Label(appointment.attended ? "Mark not done" : "Mark done",
                      systemImage: appointment.attended ? "arrow.uturn.backward" : "checkmark")
            }
            if !appointment.attended, let onReschedule {
                Button(action: onReschedule) {
                    Label("Reschedule", systemImage: "calendar")
                }
            }
            Button(role: .destructive) {
                store.deleteAppointment(appointment)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Add a new appointment, or move an existing one to a new date. When
/// rescheduling, the type is fixed and only the date changes.
struct AppointmentEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let rescheduling: Appointment?
    @State private var kind: Appointment.Kind
    @State private var date: Date

    init(draft: AppointmentDraft) {
        rescheduling = draft.rescheduling
        _kind = State(initialValue: draft.kind)
        _date = State(initialValue: Day.date(from: draft.day))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(Appointment.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(rescheduling != nil)
                    .listRowSeparator(.hidden)

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("IsoTrack only tracks whether the appointment happened. It doesn't store results.")
                }

                if let rescheduling {
                    Section {
                        Button("Delete appointment", role: .destructive) {
                            store.deleteAppointment(rescheduling)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(rescheduling == nil ? "New appointment" : "Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let day = Day.string(from: date)
                        if let rescheduling {
                            store.rescheduleAppointment(rescheduling, to: day)
                        } else {
                            store.addAppointment(day: day, kind: kind)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationSizing(.form)
    }
}

// MARK: - Supply

struct SupplyCard: View {
    @Environment(AppStore.self) private var store
    let edit: () -> Void

    var body: some View {
        let course = store.course
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Pill supply") {
                if store.refill != nil {
                    Button("Edit", action: edit)
                        .font(.caption.weight(.semibold))
                        .accessibilityLabel("Edit pill supply")
                }
            }

            if let refill = store.refill {
                let days = course.refillDaysLeft ?? 0
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(refill.pillsLeft)")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(refill.pillsLeft)))
                    Text(refill.pillsLeft == 1 ? "pill left" : "pills left")
                        .font(.display(.headline))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if course.refillIsLow {
                        Text("Refill soon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warn)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 26)
                            .background(Color.warn.opacity(0.14), in: Capsule())
                    }
                }
                .animation(Motion.spring, value: refill.pillsLeft)

                MeterBar(value: Double(refill.pillsLeft) / Double(max(1, refill.boxSize)),
                         tint: course.refillIsLow ? .warn : .good)

                Text("About \(days) \(days == 1 ? "day" : "days") at your usual \(course.pillsPerDay) \(course.pillsPerDay == 1 ? "pill" : "pills") a day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    store.addBox()
                } label: {
                    Label("Picked up a box of \(refill.boxSize)", systemImage: "shippingbox.fill")
                        .symbolEffect(.bounce, value: refill.pillsLeft)
                }
                .buttonStyle(SoftButtonStyle())
                .sensoryFeedback(.impact(weight: .medium), trigger: refill.pillsLeft)
            } else {
                InfoRow(symbol: "shippingbox.fill", tint: .good,
                        title: "Never run out",
                        detail: "Count pills down as you log and get a heads-up before they're gone.")
                Button("Track my supply", action: edit)
                    .buttonStyle(SoftButtonStyle())
            }
        }
        .card()
    }
}

struct SupplyEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = true
    @State private var pillsLeft = 30
    @State private var boxSize = 30

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Track pill supply", isOn: $enabled)
                } footer: {
                    Text("Counts down as you log doses. You'll get a notification about a day before you run out.")
                }

                if enabled {
                    Section {
                        Stepper(value: $pillsLeft, in: 0...999) {
                            LabeledContent("Pills on hand", value: "\(pillsLeft)")
                        }
                        Stepper(value: $boxSize, in: 10...300, step: 10) {
                            LabeledContent("Pills per box", value: "\(boxSize)")
                        }
                    }
                }
            }
            .navigationTitle("Pill supply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateRefill(enabled: enabled, pillsLeft: pillsLeft, boxSize: boxSize)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .animation(.snappy, value: enabled)
        }
        .presentationDetents([.medium, .large])
        .presentationSizing(.form)
        .onAppear {
            if let refill = store.refill {
                pillsLeft = refill.pillsLeft
                boxSize = refill.boxSize
            }
        }
    }
}
