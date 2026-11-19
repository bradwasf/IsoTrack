import SwiftUI
import UniformTypeIdentifiers

/// Weight units for entry and display. Stored as kilograms either way.
enum WeightUnit: String, CaseIterable, Identifiable {
    case lb, kg

    var id: String { rawValue }

    static let poundsPerKg = 2.2046226218

    /// Pounds where the locale uses US or UK customary weights, else kilograms.
    static var localeDefault: WeightUnit {
        Locale.current.measurementSystem == .metric ? .kg : .lb
    }

    func value(fromKg kg: Double) -> Double {
        let raw = self == .lb ? kg * Self.poundsPerKg : kg
        return (raw * 10).rounded() / 10
    }

    func kilograms(from value: Double) -> Double {
        self == .lb ? value / Self.poundsPerKg : value
    }
}

/// The goal choices offered in onboarding and Settings.
enum GoalChoice: Hashable, Identifiable {
    case perKg(Double)
    case customTotal

    static let presets: [GoalChoice] = [.perKg(120), .perKg(130), .perKg(140), .perKg(150), .customTotal]

    var id: String { title }

    var title: String {
        switch self {
        case .perKg(let value): return "\(Int(value))"
        case .customTotal: return "Custom"
        }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .dark
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .localeDefault

    @State private var weight: Double?
    @State private var priorMg: Double?
    @State private var goal: GoalChoice = .perKg(150)
    @State private var customGoalTotal: Double?

    @State private var reminderEnabled = ReminderManager.shared.enabled
    @State private var reminderTime = Date()
    @State private var notificationsDenied = false

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var pendingRestore: Data?
    @State private var restoreError: String?
    @State private var showEraseConfirm = false

    private var weightKg: Double? {
        guard let weight, weight > 0 else { return nil }
        return weightUnit.kilograms(from: weight)
    }

    private var profileIsValid: Bool {
        guard weightKg != nil else { return false }
        if goal == .customTotal { return (customGoalTotal ?? 0) > 0 }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                scheduleSection
                reminderSection
                appearanceSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!profileIsValid)
                }
            }
        }
        .presentationSizing(.form)
        .onAppear(perform: loadState)
        .onChange(of: weightUnit) { old, new in
            // Keep the same physical weight when the unit flips.
            if let weight { self.weight = new.value(fromKg: old.kilograms(from: weight)) }
        }
        .onChange(of: reminderEnabled) { _, isOn in setReminder(isOn) }
        .onChange(of: reminderTime) { _, newTime in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
            ReminderManager.shared.minutesFromMidnight = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
            store.resyncReminders()
        }
        .alert("Notifications are off", isPresented: $notificationsDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn them on for IsoTrack in the Settings app under Notifications.")
        }
        .alert("Couldn't restore", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreError ?? "")
        }
        .confirmationDialog(
            "Replace everything in IsoTrack with this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace my data", role: .destructive) {
                if let data = pendingRestore { restore(data) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current doses, appointments and notes will be overwritten.")
        }
        .confirmationDialog(
            "This erases your profile and everything you've logged.",
            isPresented: $showEraseConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) {
                store.eraseAll()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pendingRestore = data
            } else {
                restoreError = "That file couldn't be opened."
            }
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section {
            LabeledContent("Weight") {
                HStack(spacing: 10) {
                    TextField("0", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Picker("Unit", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            LabeledContent("Taken before tracking") {
                HStack(spacing: 6) {
                    TextField("0", value: $priorMg, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("mg").foregroundStyle(.secondary)
                }
            }
            Picker("Goal", selection: $goal) {
                ForEach(GoalChoice.presets) { choice in
                    switch choice {
                    case .perKg(let value): Text("\(Int(value)) mg/kg").tag(choice)
                    case .customTotal: Text("Custom total").tag(choice)
                    }
                }
            }
            if goal == .customTotal {
                LabeledContent("Goal total") {
                    HStack(spacing: 6) {
                        TextField("e.g. 15000", value: $customGoalTotal, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("mg").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Course")
        } footer: {
            if let target = previewTarget {
                Text("Your goal works out to \(CourseSnapshot.whole(target)) mg. Use the goal your dermatologist set.")
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            NavigationLink {
                ScheduleView()
            } label: {
                LabeledContent("Dose schedule") {
                    Text(store.schedule.isEmpty
                         ? "Off"
                         : "\(store.schedule.count) a day · \(CourseSnapshot.trimmed(store.course.scheduledMg)) mg")
                }
            }
            .accessibilityIdentifier("dose-schedule")
        } footer: {
            Text("Split your day into separate doses — like 60 mg with your first meal and 30 mg with your second — and tick each one off on the Today tab.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Daily reminder", isOn: $reminderEnabled)
            if reminderEnabled {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
            }
        } footer: {
            if store.schedule.contains(where: { $0.reminderMinutes != nil }) {
                Text("Your dose schedule has its own reminder times, so those are used instead of this daily reminder.")
            } else {
                Text("The notification has a one-tap button to log your next dose, and it's skipped once today is logged.")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export a backup", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                showImporter = true
            } label: {
                Label("Restore from a backup", systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive) {
                showEraseConfirm = true
            } label: {
                Label("Erase all data", systemImage: "trash")
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Everything stays on this iPhone. Export a backup now and then so you have a copy if you ever delete the app.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        } footer: {
            Text("IsoTrack is a personal tracking tool, not medical advice. Always follow your dermatologist's dosing plan.")
        }
    }

    // MARK: Actions

    private var previewTarget: Double? {
        switch goal {
        case .customTotal: return (customGoalTotal ?? 0) > 0 ? customGoalTotal : nil
        case .perKg(let value): return weightKg.map { $0 * value }
        }
    }

    private func loadState() {
        if let p = store.profile {
            weight = weightUnit.value(fromKg: p.weightKg)
            priorMg = p.priorMg
            if let total = p.goalTotalMg, total > 0 {
                goal = .customTotal
                customGoalTotal = total
            } else if GoalChoice.presets.contains(.perKg(p.goalMgKg)) {
                goal = .perKg(p.goalMgKg)
            } else {
                // A per-kg goal outside the presets: keep its exact total.
                goal = .customTotal
                customGoalTotal = (p.goalMgKg * p.weightKg).rounded()
            }
        }
        let minutes = ReminderManager.shared.minutesFromMidnight
        reminderTime = Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
        prepareExportFile()
    }

    private func saveProfile() {
        guard profileIsValid, let weightKg, let profile = store.profile else { return }
        // Don't let a lb ↔ kg round trip nudge a weight the user didn't touch.
        let unchanged = weight == weightUnit.value(fromKg: profile.weightKg)
        let kg = unchanged ? profile.weightKg : (weightKg * 10).rounded() / 10
        switch goal {
        case .customTotal:
            store.updateProfile(weightKg: kg, priorMg: priorMg ?? 0, goalMgKg: 150, goalTotalMg: customGoalTotal)
        case .perKg(let value):
            store.updateProfile(weightKg: kg, priorMg: priorMg ?? 0, goalMgKg: value, goalTotalMg: nil)
        }
    }

    private func setReminder(_ isOn: Bool) {
        guard isOn else {
            ReminderManager.shared.enabled = false
            store.resyncReminders()
            return
        }
        ReminderManager.shared.requestAuthorization { granted in
            if granted {
                ReminderManager.shared.enabled = true
                store.resyncReminders()
            } else {
                reminderEnabled = false
                notificationsDenied = true
            }
        }
    }

    private func prepareExportFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("isotrack-backup-\(Day.today).json")
        do {
            try store.exportData().write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    private func restore(_ data: Data) {
        do {
            try store.restore(from: data)
            dismiss()
        } catch {
            restoreError = error.localizedDescription
        }
    }
}
