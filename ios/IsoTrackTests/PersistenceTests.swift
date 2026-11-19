import XCTest
@testable import IsoTrack

/// Guards the on-disk format. If one of these fails, a new build would lose
/// or corrupt the data already sitting on someone's phone.
final class PersistenceTests: XCTestCase {
    /// Byte-for-byte what the 1.0 app wrote (generated with the 1.0 models).
    static let legacyJSON = #"""
    {"refill":{"boxSize":60,"pillsLeft":41},"entries":[{"id":"E1","date":"2026-08-01","mg":40,"pills":1},{"pills":2,"mg":40,"id":"E2","date":"2026-08-02"},{"mg":37.5,"pills":2,"date":"2026-08-04","id":"E3"}],"profile":{"goalMgKg":150,"weightKg":68.5,"priorMg":900,"startedISO":"2026-08-01"},"appointments":[{"kind":"bloodDraw","attended":true,"day":"2026-08-15","id":"A1"},{"kind":"dermVisit","attended":false,"day":"2026-09-15","id":"A2"}]}
    """#

    private var url: URL!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("isotrack-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(SharedStore.fileName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        super.tearDown()
    }

    private func writeLegacyFile() throws {
        try Data(Self.legacyJSON.utf8).write(to: url)
    }

    private func makeStore() -> AppStore {
        AppStore(url: url, syncsSystem: false)
    }

    // MARK: Contract

    func testStorageLocationIsUnchanged() {
        // The App Group is always "group." + the app's bundle id (the test host).
        XCTAssertEqual(SharedStore.appGroupId, "group." + (Bundle.main.bundleIdentifier ?? ""))
        XCTAssertEqual(SharedStore.fileName, "isotrack-data.json")
        XCTAssertEqual(SharedStore.dataURL.lastPathComponent, "isotrack-data.json")
    }

    func testLegacyFileLoadsCompletely() throws {
        try writeLegacyFile()
        let store = makeStore()

        XCTAssertEqual(store.profile, UserProfile(weightKg: 68.5, priorMg: 900, goalMgKg: 150,
                                                  goalTotalMg: nil, startedDay: "2026-08-01"))
        XCTAssertEqual(store.entries.map(\.id), ["E1", "E2", "E3"])
        XCTAssertEqual(store.entries[2], DoseEntry(id: "E3", day: "2026-08-04", mgPerPill: 37.5, pillCount: 2))
        XCTAssertEqual(store.refill, RefillInfo(pillsLeft: 41, boxSize: 60))
        XCTAssertEqual(store.appointments, [
            Appointment(id: "A1", day: "2026-08-15", kind: .bloodDraw, attended: true),
            Appointment(id: "A2", day: "2026-09-15", kind: .dermVisit, attended: false),
        ])
        XCTAssertTrue(store.checkIns.isEmpty)
        XCTAssertEqual(store.course.cumulativeMg, 900 + 40 + 80 + 75)
        XCTAssertEqual(store.course.goalMg, 150 * 68.5, accuracy: 0.001)
    }

    func testSavingKeepsEveryLegacyKey() throws {
        try writeLegacyFile()
        let store = makeStore()
        store.addDose(day: "2026-08-05", mgPerPill: 40, pillCount: 2)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let profile = try XCTUnwrap(object["profile"] as? [String: Any])
        XCTAssertEqual(Set(profile.keys), ["weightKg", "priorMg", "goalMgKg", "startedISO"])
        XCTAssertEqual(profile["startedISO"] as? String, "2026-08-01")

        let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(Set(entries[0].keys), ["id", "date", "mg", "pills"])

        let refill = try XCTUnwrap(object["refill"] as? [String: Any])
        XCTAssertEqual(refill["pillsLeft"] as? Int, 39)
        XCTAssertEqual(refill["boxSize"] as? Int, 60)

        let appointments = try XCTUnwrap(object["appointments"] as? [[String: Any]])
        XCTAssertEqual(Set(appointments[0].keys), ["id", "day", "kind", "attended"])
        XCTAssertEqual(appointments.map { $0["kind"] as? String }, ["bloodDraw", "dermVisit"])
    }

    func testDataSurvivesARelaunch() throws {
        try writeLegacyFile()
        let first = makeStore()
        first.addDose(day: "2026-08-05", mgPerPill: 40, pillCount: 2)
        first.saveCheckIn(day: "2026-08-05", symptoms: ["dryLips": 2, "drySkin": 0], note: "  lips  ")
        first.addAppointment(day: "2026-10-15", kind: .bloodDraw)

        let second = makeStore()
        XCTAssertEqual(second.entries.count, 4)
        XCTAssertEqual(second.appointments.count, 3)
        XCTAssertEqual(second.checkIns.count, 1)
        XCTAssertEqual(second.checkIns[0].symptoms, ["dryLips": 2])
        XCTAssertEqual(second.checkIns[0].note, "lips")
        XCTAssertEqual(second.profile, first.profile)
    }

    // MARK: Safety nets

    func testUnreadableFileIsSetAsideNotOverwritten() throws {
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: url)

        let store = makeStore()
        XCTAssertNil(store.profile)

        let dir = url.deletingLastPathComponent()
        let saved = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("unreadable") }
        XCTAssertEqual(saved.count, 1, "the unreadable file should be kept for recovery")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(saved[0])), garbage)
    }

    func testCorruptFileFallsBackToDailySnapshot() throws {
        try writeLegacyFile()
        // The first save of the day snapshots the file as it was.
        makeStore().addDose(day: "2026-08-05", mgPerPill: 40, pillCount: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: SharedStore.snapshotURL(for: url).path))

        try Data("garbage".utf8).write(to: url)
        let recovered = makeStore()
        XCTAssertEqual(recovered.entries.map(\.id), ["E1", "E2", "E3"])
        XCTAssertNotNil(recovered.profile)
        // …and the recovered data is written back as the main file.
        XCTAssertEqual(SharedStore.loadBackup(at: url)?.entries.count, 3)
    }

    func testRefreshNeverForgetsDataHeldInMemory() throws {
        try writeLegacyFile()
        let store = makeStore()

        // The file disappears, then turns to garbage, while the app is open.
        try FileManager.default.removeItem(at: url)
        store.refresh()
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(SharedStore.loadBackup(at: url)?.entries.count, 3, "the file is put back")

        try Data("garbage".utf8).write(to: url)
        store.refresh()
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(SharedStore.loadBackup(at: url)?.entries.count, 3)
    }

    func testOneBadAppointmentDoesNotLoseTheFile() throws {
        let json = #"""
        {"entries":[{"id":"E1","date":"2026-08-01","mg":40,"pills":1}],"profile":{"goalMgKg":150,"weightKg":70,"priorMg":0},"appointments":[{"kind":"somethingNew","attended":true,"day":"2026-08-15","id":"A1"},{"kind":"dermVisit","attended":false,"day":"2026-09-15","id":"A2"}],"checkIns":[{"id":"C1","day":"2026-08-02","symptoms":{"futureSymptom":3}}]}
        """#
        try Data(json.utf8).write(to: url)
        let store = makeStore()
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.appointments.map(\.id), ["A2"])
        XCTAssertEqual(store.checkIns.first?.symptoms, ["futureSymptom": 3])
    }

    func testRestoreRejectsFilesWithoutAProfile() throws {
        try writeLegacyFile()
        let store = makeStore()
        XCTAssertThrowsError(try store.restore(from: Data("nope".utf8)))
        XCTAssertThrowsError(try store.restore(from: Data(#"{"entries":[]}"#.utf8)))
        XCTAssertEqual(store.entries.count, 3, "a failed restore must leave the data alone")

        let exported = store.exportData()
        store.addDose(day: "2026-08-06", mgPerPill: 40, pillCount: 1)
        try store.restore(from: exported)
        XCTAssertEqual(store.entries.count, 3)
    }

    // MARK: Mutations

    func testDeletingADoseReturnsItsPills() throws {
        try writeLegacyFile()
        let store = makeStore()
        store.deleteEntry(store.entries[1]) // 2 pills
        XCTAssertEqual(store.refill?.pillsLeft, 43)
        XCTAssertEqual(store.entries.count, 2)
    }

    func testWidgetLoggerAppendsUsualDose() throws {
        try writeLegacyFile()
        let result = try XCTUnwrap(SharedDoseLogger.logNextDose(at: url, day: "2026-08-05", reloadWidgets: false).result)
        XCTAssertNil(result.slotLabel)
        XCTAssertEqual(result.totalMg, 75)
        XCTAssertEqual(result.cumulativeMg, 900 + 40 + 80 + 75 + 75)

        // The app picks the widget's dose up on its next refresh.
        let store = makeStore()
        XCTAssertEqual(store.entries.count, 4)
        XCTAssertEqual(store.refill?.pillsLeft, 39)
    }

    func testWidgetLoggerNeedsASetUpCourse() {
        XCTAssertEqual(SharedDoseLogger.logNextDose(at: url, reloadWidgets: false), .unavailable)
    }

    // MARK: Dose schedule

    private func addSplitSchedule(to store: AppStore) -> (first: DoseSlot, second: DoseSlot) {
        let first = DoseSlot(id: "S1", label: "First meal", mgPerPill: 30, pillCount: 2, reminderMinutes: 480)
        let second = DoseSlot(id: "S2", label: "  Second meal ", mgPerPill: 30, pillCount: 1, reminderMinutes: nil)
        store.saveSlot(first)
        store.saveSlot(second)
        return (store.schedule[0], store.schedule[1])
    }

    func testScheduleIsAddedAsOptionalKeysOnly() throws {
        try writeLegacyFile()
        let store = makeStore()
        XCTAssertTrue(store.schedule.isEmpty)

        // Saving without a schedule writes no trace of the feature.
        store.addDose(day: "2026-08-05", mgPerPill: 40, pillCount: 2)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(object["schedule"])

        let slots = addSplitSchedule(to: store)
        store.setTaken(true, slot: slots.first, day: "2026-08-06")

        object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let schedule = try XCTUnwrap(object["schedule"] as? [[String: Any]])
        XCTAssertEqual(schedule.map { $0["label"] as? String }, ["First meal", "Second meal"])
        XCTAssertEqual(Set(schedule[0].keys), ["id", "label", "mgPerPill", "pillCount", "reminderMinutes"])
        XCTAssertEqual(Set(schedule[1].keys), ["id", "label", "mgPerPill", "pillCount"])

        let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        XCTAssertEqual(Set(entries[0].keys), ["id", "date", "mg", "pills"], "old entries are untouched")
        XCTAssertEqual(entries.last?["slot"] as? String, "S1")
        XCTAssertEqual(entries.last?["mg"] as? Double, 30)
        XCTAssertEqual(entries.last?["pills"] as? Int, 2)
    }

    func testScheduleSurvivesARelaunch() throws {
        try writeLegacyFile()
        let first = makeStore()
        let slots = addSplitSchedule(to: first)
        first.setTaken(true, slot: slots.second, day: "2026-08-06")

        let second = makeStore()
        XCTAssertEqual(second.schedule, [slots.first, slots.second])
        XCTAssertEqual(second.schedule[1].label, "Second meal", "labels are trimmed")
        XCTAssertTrue(second.course.isTaken(slots.second, on: "2026-08-06"))
        XCTAssertFalse(second.course.isTaken(slots.first, on: "2026-08-06"))
    }

    func testTickingADoseOnAndOff() throws {
        try writeLegacyFile()
        let store = makeStore()
        let slots = addSplitSchedule(to: store)
        let day = "2026-08-06"

        store.setTaken(true, slot: slots.first, day: day)
        store.setTaken(true, slot: slots.first, day: day) // a second tap can't double-log
        XCTAssertEqual(store.course.entries(on: day).count, 1)
        XCTAssertEqual(store.course.mg(on: day), 60)
        XCTAssertEqual(store.refill?.pillsLeft, 39)
        XCTAssertFalse(store.course.isComplete(on: day))

        store.setTaken(true, slot: slots.second, day: day)
        XCTAssertEqual(store.course.mg(on: day), 90)
        XCTAssertEqual(store.refill?.pillsLeft, 38)
        XCTAssertTrue(store.course.isComplete(on: day))

        store.setTaken(false, slot: slots.first, day: day)
        XCTAssertEqual(store.course.mg(on: day), 30)
        XCTAssertEqual(store.refill?.pillsLeft, 40, "unticking returns the pills")
        XCTAssertEqual(store.entries.count, 4)
    }

    func testConfettiWaitsForTheLastDoseOfTheDay() throws {
        try writeLegacyFile()
        let store = makeStore()
        let slots = addSplitSchedule(to: store)
        let confetti = store.confettiTrigger
        let pulse = store.logPulse

        store.setTaken(true, slot: slots.first, day: "2026-08-06")
        XCTAssertEqual(store.logPulse, pulse + 1)
        XCTAssertEqual(store.confettiTrigger, confetti)

        store.setTaken(true, slot: slots.second, day: "2026-08-06")
        XCTAssertEqual(store.confettiTrigger, confetti + 1)
    }

    func testEditingTheScheduleKeepsLoggedHistory() throws {
        try writeLegacyFile()
        let store = makeStore()
        let slots = addSplitSchedule(to: store)
        store.setTaken(true, slot: slots.first, day: "2026-08-06")

        var changed = slots.first
        changed.pillCount = 1
        store.saveSlot(changed)
        XCTAssertEqual(store.schedule.count, 2, "same id replaces, not appends")
        XCTAssertEqual(store.course.mg(on: "2026-08-06"), 60, "the logged dose keeps its strength")
        XCTAssertTrue(store.course.isTaken(changed, on: "2026-08-06"))

        store.deleteSlot(changed)
        XCTAssertEqual(store.schedule.map(\.id), ["S2"])
        XCTAssertEqual(store.course.mg(on: "2026-08-06"), 60, "removing a slot keeps what it logged")

        store.clearSchedule()
        XCTAssertTrue(store.schedule.isEmpty)
        XCTAssertNil(SharedStore.loadBackup(at: url)?.schedule)
    }

    func testReorderingTheSchedule() throws {
        try writeLegacyFile()
        let store = makeStore()
        _ = addSplitSchedule(to: store)
        store.saveSlot(DoseSlot(id: "S3", label: "Bedtime", mgPerPill: 10, pillCount: 1, reminderMinutes: nil))

        store.moveSlots(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.schedule.map(\.id), ["S3", "S1", "S2"])
        store.moveSlots(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(store.schedule.map(\.id), ["S1", "S2", "S3"])
        XCTAssertEqual(makeStore().schedule.map(\.id), ["S1", "S2", "S3"])
    }

    func testCatchingUpAFullDayAndLoggingTheNextDose() throws {
        try writeLegacyFile()
        let store = makeStore()
        _ = addSplitSchedule(to: store)

        store.logNextDose(day: "2026-08-06")
        XCTAssertEqual(store.course.mg(on: "2026-08-06"), 60)
        store.logNextDose(day: "2026-08-06")
        store.logNextDose(day: "2026-08-06") // nothing left to tick
        XCTAssertEqual(store.course.mg(on: "2026-08-06"), 90)

        store.logFullDay("2026-08-07")
        XCTAssertEqual(store.course.entries(on: "2026-08-07").compactMap(\.slotId), ["S1", "S2"])
    }

    func testWidgetLoggerTicksTheNextScheduledDose() throws {
        try writeLegacyFile()
        _ = addSplitSchedule(to: makeStore())
        let day = "2026-08-06"

        let first = try XCTUnwrap(SharedDoseLogger.logNextDose(at: url, day: day, reloadWidgets: false).result)
        XCTAssertEqual(first.totalMg, 60)
        XCTAssertEqual(first.slotLabel, "First meal")
        XCTAssertEqual(first.remainingSlots, 1)

        let second = try XCTUnwrap(SharedDoseLogger.logNextDose(at: url, day: day, reloadWidgets: false).result)
        XCTAssertEqual(second.totalMg, 30)
        XCTAssertEqual(second.remainingSlots, 0)
        XCTAssertEqual(second.cumulativeMg, 900 + 40 + 80 + 75 + 90)

        XCTAssertEqual(SharedDoseLogger.logNextDose(at: url, day: day, reloadWidgets: false), .nothingDue)

        // The app sees both as ticked boxes on its next refresh.
        let store = makeStore()
        XCTAssertEqual(store.course.takenSlotCount(on: day), 2)
        XCTAssertEqual(store.refill?.pillsLeft, 38)
    }

    func testOneBadScheduledDoseDoesNotLoseTheFile() throws {
        let json = #"""
        {"entries":[{"id":"E1","date":"2026-08-01","mg":40,"pills":1,"slot":"gone"}],"profile":{"goalMgKg":150,"weightKg":70,"priorMg":0},"schedule":[{"id":"S1","label":"First meal","mgPerPill":30,"pillCount":2},{"id":"S2","label":"Broken"},{"id":"S3","label":"Zero","mgPerPill":0,"pillCount":1}]}
        """#
        try Data(json.utf8).write(to: url)
        let store = makeStore()
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].slotId, "gone")
        XCTAssertEqual(store.schedule.map(\.id), ["S1"])
    }

    func testEraseRemovesFileAndSnapshot() throws {
        try writeLegacyFile()
        let store = makeStore()
        store.addDose(day: "2026-08-05", mgPerPill: 40, pillCount: 2)
        store.eraseAll()
        XCTAssertNil(store.profile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: SharedStore.snapshotURL(for: url).path))
    }
}
