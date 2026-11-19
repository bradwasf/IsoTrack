import Foundation
import Observation
import WidgetKit

/// The app's single source of truth: loads and saves the shared data file and
/// exposes every mutation the UI can make.
@Observable
final class AppStore {
    private(set) var profile: UserProfile?
    private(set) var entries: [DoseEntry] = []
    private(set) var refill: RefillInfo?
    private(set) var appointments: [Appointment] = []
    private(set) var checkIns: [CheckIn] = []
    /// The planned doses for each day, in order. Empty = one usual dose a day.
    private(set) var schedule: [DoseSlot] = []

    /// "Today" as the UI sees it; refreshed when the calendar day rolls over.
    private(set) var today: String = Day.today

    /// Bumped every time a dose is logged: a haptic and a pulse of the ring.
    private(set) var logPulse = 0
    /// Bumped when a day's dosing is finished (or a milestone is crossed) so
    /// the confetti layer fires. Ticking off one dose of several doesn't.
    private(set) var confettiTrigger = 0
    /// Set when the last logged dose crossed a milestone.
    private(set) var celebration: Celebration?

    struct Celebration: Equatable, Identifiable {
        let id = UUID()
        var title: String
        var detail: String
    }

    @ObservationIgnored private let url: URL
    /// False in tests and UI-test runs: no widget reloads or notifications.
    @ObservationIgnored private let syncsSystem: Bool

    init(url: URL = SharedStore.dataURL, syncsSystem: Bool = true) {
        self.url = url
        self.syncsSystem = syncsSystem
        if url == SharedStore.dataURL {
            migrateLegacyStoreIfNeeded()
        }
        load()
    }

    /// Everything derived from the stored data.
    var course: CourseSnapshot {
        CourseSnapshot(profile: profile, entries: entries, refill: refill, schedule: schedule, today: today)
    }

    // MARK: - Persistence

    /// 1.0 builds stored data in Documents; copy it into the shared App Group
    /// container so the widget can read it. Never overwrites existing data.
    private func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        let legacy = SharedStore.legacyDocumentsURL
        guard legacy != url,
              fm.fileExists(atPath: legacy.path),
              !fm.fileExists(atPath: url.path) else { return }
        try? fm.copyItem(at: legacy, to: url)
    }

    func load() {
        today = Day.today
        switch SharedStore.read(at: url) {
        case .loaded(let backup):
            apply(backup)
        case .missing:
            // If the file vanished while the app was holding a course in
            // memory, put it back rather than forgetting everything.
            if profile != nil {
                SharedStore.write(backup, to: url)
            }
        case .unreadable:
            // Never silently replace a file we couldn't read: set it aside.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            if profile != nil {
                // Mid-session: what's in memory is the freshest good copy.
                SharedStore.write(backup, to: url)
            } else if let snapshot = SharedStore.loadBackup(at: SharedStore.snapshotURL(for: url)) {
                // At launch: fall back to the last daily snapshot.
                apply(snapshot)
                SharedStore.write(snapshot, to: url)
            }
        }
    }

    private func apply(_ backup: Backup?) {
        profile = backup?.domainProfile
        entries = (backup?.domainEntries ?? []).sorted { $0.day < $1.day }
        refill = backup?.refill
        appointments = (backup?.appointments ?? []).sorted { $0.day < $1.day }
        checkIns = (backup?.checkIns ?? []).sorted { $0.day < $1.day }
        schedule = backup?.domainSchedule ?? []
    }

    private var backup: Backup {
        Backup(profile: profile, entries: entries, refill: refill,
               appointments: appointments, checkIns: checkIns, schedule: schedule)
    }

    private func save() {
        SharedStore.write(backup, to: url)
        guard syncsSystem else { return }
        WidgetCenter.shared.reloadAllTimelines()
        resyncReminders()
    }

    func resyncReminders() {
        guard syncsSystem else { return }
        ReminderManager.shared.reschedule(course: course, appointments: appointments)
    }

    /// Called when the app becomes active: picks up doses logged from the
    /// widget or Siri and rolls "today" forward after midnight.
    func refresh() {
        load()
        resyncReminders()
    }

    func exportData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(backup)) ?? Data()
    }

    enum RestoreError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file isn't an IsoTrack backup."
            case .empty: return "That backup doesn't contain a course profile."
            }
        }
    }

    /// Replaces everything with the contents of an exported backup file.
    func restore(from data: Data) throws {
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            throw RestoreError.unreadable
        }
        guard backup.profile != nil else { throw RestoreError.empty }
        apply(backup)
        save()
    }

    // MARK: - Profile

    func completeOnboarding(weightKg: Double, priorMg: Double, goalMgKg: Double, goalTotalMg: Double? = nil) {
        let roundedKg = (weightKg * 10).rounded() / 10
        profile = UserProfile(
            weightKg: roundedKg,
            priorMg: max(0, priorMg),
            // Keep mg/kg meaningful even when using a custom total.
            goalMgKg: goalTotalMg.map { ($0 / roundedKg * 10).rounded() / 10 } ?? goalMgKg,
            goalTotalMg: goalTotalMg,
            startedDay: Day.today
        )
        save()
    }

    func updateProfile(weightKg: Double, priorMg: Double, goalMgKg: Double, goalTotalMg: Double? = nil) {
        guard var p = profile, weightKg > 0 else { return }
        p.weightKg = weightKg
        p.priorMg = max(0, priorMg)
        p.goalMgKg = goalTotalMg.map { ($0 / weightKg * 10).rounded() / 10 } ?? goalMgKg
        p.goalTotalMg = goalTotalMg
        profile = p
        save()
    }

    func eraseAll() {
        SharedStore.removeAll(at: url)
        apply(nil)
        guard syncsSystem else { return }
        WidgetCenter.shared.reloadAllTimelines()
        resyncReminders()
    }

    // MARK: - Doses

    func addDose(day: String, mgPerPill: Double, pillCount: Int, slotId: String? = nil) {
        guard mgPerPill > 0, pillCount > 0 else { return }
        let before = course
        entries.append(DoseEntry(id: UUID().uuidString, day: day, mgPerPill: mgPerPill,
                                 pillCount: pillCount, slotId: slotId))
        entries.sort { $0.day < $1.day }
        if var r = refill {
            r.pillsLeft = max(0, r.pillsLeft - pillCount)
            refill = r
        }
        save()

        let after = course
        let crossed = before.milestonesCrossed(from: before.cumulativeMg, to: after.cumulativeMg)
        celebration = crossed.last.map {
            Celebration(title: $0.id == "goal" ? "Goal reached!" : $0.title,
                        detail: "\($0.detail) cumulative")
        }
        logPulse += 1
        // Save the confetti for the dose that finishes the day.
        if celebration != nil || (after.isComplete(on: day) && !before.isComplete(on: day)) || !after.hasSchedule {
            confettiTrigger += 1
        }
    }

    func addUsualDose(day: String? = nil) {
        let usual = course.usualDose
        addDose(day: day ?? today, mgPerPill: usual.mgPerPill, pillCount: usual.pillCount)
    }

    /// One-tap logging from a notification: the next scheduled dose still due
    /// on `day` (nothing, if they're all ticked off), else the usual dose.
    func logNextDose(day: String? = nil) {
        let day = day ?? today
        let course = course
        guard course.hasSchedule else { return addUsualDose(day: day) }
        if let slot = course.pendingSlots(on: day).first {
            setTaken(true, slot: slot, day: day)
        }
    }

    /// Ticks every scheduled dose still open on `day` (catching up a missed
    /// day); without a schedule, logs the usual dose.
    func logFullDay(_ day: String) {
        let course = course
        guard course.hasSchedule else { return addUsualDose(day: day) }
        for slot in course.pendingSlots(on: day) {
            setTaken(true, slot: slot, day: day)
        }
    }

    func deleteEntry(_ entry: DoseEntry) {
        guard entries.contains(where: { $0.id == entry.id }) else { return }
        entries.removeAll { $0.id == entry.id }
        if var r = refill {
            r.pillsLeft += entry.pillCount
            refill = r
        }
        save()
    }

    func dismissCelebration() {
        celebration = nil
    }

    // MARK: - Schedule

    /// Ticks a scheduled dose on or off for `day`. On logs an entry with the
    /// slot's current strength and count; off removes that entry again.
    func setTaken(_ taken: Bool, slot: DoseSlot, day: String? = nil) {
        let day = day ?? today
        let existing = course.entry(for: slot, on: day)
        if taken, existing == nil {
            addDose(day: day, mgPerPill: slot.mgPerPill, pillCount: slot.pillCount, slotId: slot.id)
        } else if !taken, let existing {
            deleteEntry(existing)
        }
    }

    /// Adds a scheduled dose, or replaces the one with the same id. Doses
    /// already logged keep the strength they were logged with.
    func saveSlot(_ slot: DoseSlot) {
        guard slot.mgPerPill > 0, slot.pillCount > 0 else { return }
        var cleaned = slot
        cleaned.label = slot.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.label.isEmpty { cleaned.label = "Dose" }
        if let index = schedule.firstIndex(where: { $0.id == slot.id }) {
            schedule[index] = cleaned
        } else {
            schedule.append(cleaned)
        }
        save()
    }

    /// Removes a scheduled dose. Entries it logged stay in the history.
    func deleteSlot(_ slot: DoseSlot) {
        schedule.removeAll { $0.id == slot.id }
        save()
    }

    func moveSlots(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { schedule[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        schedule.removeAll { slot in moving.contains { $0.id == slot.id } }
        schedule.insert(contentsOf: moving, at: min(max(0, insertAt), schedule.count))
        save()
    }

    /// Back to logging one usual dose a day.
    func clearSchedule() {
        guard !schedule.isEmpty else { return }
        schedule = []
        save()
    }

    // MARK: - Refill

    func updateRefill(enabled: Bool, pillsLeft: Int, boxSize: Int) {
        refill = enabled ? RefillInfo(pillsLeft: max(0, pillsLeft), boxSize: max(1, boxSize)) : nil
        save()
    }

    /// "I picked up a new box."
    func addBox() {
        guard var r = refill else { return }
        r.pillsLeft += r.boxSize
        refill = r
        save()
    }

    // MARK: - Appointments

    func addAppointment(day: String, kind: Appointment.Kind) {
        appointments.append(Appointment(id: UUID().uuidString, day: day, kind: kind, attended: false))
        appointments.sort { $0.day < $1.day }
        save()
    }

    /// Move a still-unattended appointment to a new date.
    func rescheduleAppointment(_ appointment: Appointment, to day: String) {
        guard let index = appointments.firstIndex(where: { $0.id == appointment.id }) else { return }
        appointments[index].day = day
        appointments.sort { $0.day < $1.day }
        save()
    }

    func setAttended(_ appointment: Appointment, _ attended: Bool) {
        guard let index = appointments.firstIndex(where: { $0.id == appointment.id }) else { return }
        appointments[index].attended = attended
        save()
    }

    func deleteAppointment(_ appointment: Appointment) {
        appointments.removeAll { $0.id == appointment.id }
        save()
    }

    /// Unattended appointments whose scheduled date has already passed.
    var overdueAppointments: [Appointment] {
        appointments.filter { !$0.attended && $0.day < today }
    }

    /// Unattended appointments from today onwards, soonest first.
    var upcomingAppointments: [Appointment] {
        appointments.filter { !$0.attended && $0.day >= today }
    }

    var attendedAppointments: [Appointment] {
        appointments.filter(\.attended).sorted { $0.day > $1.day }
    }

    /// A sensible date for the next appointment of this kind: about a month
    /// after the most recent one, but never in the past.
    func suggestedDay(for kind: Appointment.Kind) -> String {
        guard let last = appointments.last(where: { $0.kind == kind }) else { return today }
        return max(today, Day.adding(30, to: last.day))
    }

    // MARK: - Check-ins

    func checkIn(on day: String) -> CheckIn? {
        checkIns.first { $0.day == day }
    }

    /// Saves the check-in for a day, replacing any existing one. An empty
    /// check-in (no symptoms, no note) removes it.
    func saveCheckIn(day: String, symptoms: [String: Int], note: String) {
        let cleaned = symptoms.filter { $0.value > 0 }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = checkIn(on: day)
        checkIns.removeAll { $0.day == day }
        if !cleaned.isEmpty || !trimmedNote.isEmpty {
            checkIns.append(CheckIn(id: existing?.id ?? UUID().uuidString, day: day,
                                    symptoms: cleaned, note: trimmedNote.isEmpty ? nil : trimmedNote))
            checkIns.sort { $0.day < $1.day }
        }
        save()
    }

    func deleteCheckIn(_ checkIn: CheckIn) {
        checkIns.removeAll { $0.id == checkIn.id }
        save()
    }
}
