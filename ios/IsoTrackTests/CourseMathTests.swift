import XCTest
@testable import IsoTrack

final class CourseMathTests: XCTestCase {
    private let today = "2026-11-17"

    private func profile(weightKg: Double = 70, prior: Double = 0, goalMgKg: Double = 150,
                         goalTotal: Double? = nil) -> UserProfile {
        UserProfile(weightKg: weightKg, priorMg: prior, goalMgKg: goalMgKg, goalTotalMg: goalTotal, startedDay: nil)
    }

    /// One 2 × 40 mg dose on each of the given day offsets back from today.
    private func doses(daysAgo offsets: [Int], mg: Double = 40, pills: Int = 2) -> [DoseEntry] {
        offsets.map { DoseEntry(id: "d\($0)", day: Day.adding(-$0, to: today), mgPerPill: mg, pillCount: pills) }
    }

    private func course(_ entries: [DoseEntry], profile: UserProfile? = nil, refill: RefillInfo? = nil,
                        schedule: [DoseSlot] = []) -> CourseSnapshot {
        CourseSnapshot(profile: profile ?? self.profile(), entries: entries, refill: refill,
                       schedule: schedule, today: today)
    }

    /// 60 mg with the first meal, 30 mg with the second.
    private let split = [
        DoseSlot(id: "am", label: "First meal", mgPerPill: 30, pillCount: 2, reminderMinutes: 480),
        DoseSlot(id: "pm", label: "Second meal", mgPerPill: 30, pillCount: 1, reminderMinutes: nil),
    ]

    /// Scheduled doses ticked off on a day offset back from today.
    private func ticked(_ slots: [DoseSlot], daysAgo offset: Int) -> [DoseEntry] {
        slots.map {
            DoseEntry(id: "t\(offset)-\($0.id)", day: Day.adding(-offset, to: today),
                      mgPerPill: $0.mgPerPill, pillCount: $0.pillCount, slotId: $0.id)
        }
    }

    func testTotalsAndProgress() {
        let c = course(doses(daysAgo: [3, 2, 1]), profile: profile(prior: 1000))
        XCTAssertEqual(c.cumulativeMg, 1240)
        XCTAssertEqual(c.goalMg, 10_500)
        XCTAssertEqual(c.lowMarkMg, 8_400)
        XCTAssertEqual(c.remainingMg, 9_260)
        XCTAssertEqual(c.progress, 1240 / 10_500, accuracy: 1e-9)
        XCTAssertEqual(c.mgPerKg, 1240 / 70, accuracy: 1e-9)
        XCTAssertFalse(c.goalReached)
    }

    func testCustomTotalGoalOverridesPerKg() {
        let c = course([], profile: profile(goalTotal: 9_000))
        XCTAssertEqual(c.goalMg, 9_000)
        XCTAssertEqual(c.goalMgPerKg, 9_000 / 70, accuracy: 1e-9)
    }

    func testProgressIsCappedOnceGoalIsPassed() {
        let c = course(doses(daysAgo: [1]), profile: profile(prior: 20_000))
        XCTAssertEqual(c.progress, 1)
        XCTAssertTrue(c.goalReached)
        XCTAssertEqual(c.remainingMg, 0)
        XCTAssertNil(c.daysRemaining)
    }

    func testUsualDoseIsTheMostRecentEntry() {
        var entries = doses(daysAgo: [3, 2])
        entries.append(DoseEntry(id: "x", day: Day.adding(-1, to: today), mgPerPill: 30, pillCount: 3))
        let c = course(entries)
        XCTAssertEqual(c.usualDose.mgPerPill, 30)
        XCTAssertEqual(c.usualDose.pillCount, 3)
        XCTAssertEqual(course([]).usualTotalMg, 40)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        XCTAssertEqual(course(doses(daysAgo: [2, 1, 0])).streakDays, 3)
        XCTAssertEqual(course(doses(daysAgo: [3, 2, 1])).streakDays, 3, "today not logged yet keeps the streak")
        XCTAssertEqual(course(doses(daysAgo: [4, 3, 2])).streakDays, 0)
        XCTAssertEqual(course(doses(daysAgo: [5, 4, 2, 1])).streakDays, 2)
    }

    func testYesterdayMissed() {
        XCTAssertTrue(course(doses(daysAgo: [3, 2])).yesterdayMissed)
        XCTAssertFalse(course(doses(daysAgo: [3, 2, 1])).yesterdayMissed)
        XCTAssertFalse(course(doses(daysAgo: [1])).yesterdayMissed)
        XCTAssertFalse(course(doses(daysAgo: [0])).yesterdayMissed, "a course that starts today has no yesterday")
    }

    func testPaceCountsMissedDaysAsZero() {
        // 10 doses of 80 mg over the last 14 settled days (4 missed).
        let c = course(doses(daysAgo: [14, 13, 12, 11, 10, 8, 6, 4, 2, 1]))
        XCTAssertEqual(try XCTUnwrap(c.paceMgPerDay), 800 / 14, accuracy: 1e-9)
    }

    func testPaceDoesNotReachBackBeforeTheFirstDose() {
        let c = course(doses(daysAgo: [3, 2, 1]))
        XCTAssertEqual(try XCTUnwrap(c.paceMgPerDay), 80, accuracy: 1e-9)
    }

    func testTodayOnlyCountsTowardPaceOnceLogged() {
        XCTAssertEqual(try XCTUnwrap(course(doses(daysAgo: [2, 1])).paceMgPerDay), 80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(course(doses(daysAgo: [2, 1, 0])).paceMgPerDay), 80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(course(doses(daysAgo: [0])).paceMgPerDay), 80, accuracy: 1e-9)
        XCTAssertNil(course([]).paceMgPerDay)
    }

    func testFinishEstimate() {
        // 240 mg in, goal 400 mg at 80 mg/day → two more doses.
        let goal = profile(goalTotal: 400)
        let notLoggedToday = course(doses(daysAgo: [3, 2, 1]), profile: goal)
        XCTAssertEqual(notLoggedToday.daysRemaining, 2)
        XCTAssertEqual(notLoggedToday.estimatedFinishDay, Day.adding(1, to: today), "today and tomorrow")

        let loggedToday = course(doses(daysAgo: [2, 1, 0]), profile: goal)
        XCTAssertEqual(loggedToday.estimatedFinishDay, Day.adding(2, to: today))
        XCTAssertEqual(loggedToday.daysUntilFinish, 2)
    }

    func testAdherence() {
        XCTAssertEqual(try XCTUnwrap(course(doses(daysAgo: [4, 3, 1])).adherence), 0.75, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(course(doses(daysAgo: [2, 1, 0])).adherence), 1, accuracy: 1e-9)
        XCTAssertNil(course([]).adherence)
    }

    func testRefillDaysUseTheUsualPillCount() {
        let c = course(doses(daysAgo: [1]), refill: RefillInfo(pillsLeft: 9, boxSize: 60))
        XCTAssertEqual(c.refillDaysLeft, 4)
        XCTAssertTrue(c.refillIsLow)
        XCTAssertNil(course(doses(daysAgo: [1])).refillDaysLeft)
    }

    // MARK: Schedule

    func testScheduleTotalsAndNextDose() {
        let none = course([], schedule: split)
        XCTAssertTrue(none.hasSchedule)
        XCTAssertEqual(none.scheduledMg, 90)
        XCTAssertEqual(none.scheduledPills, 3)
        XCTAssertEqual(none.pendingSlots(on: today).map(\.id), ["am", "pm"])
        XCTAssertEqual(none.nextSlot?.id, "am")
        XCTAssertEqual(none.nextDoseMg, 60)
        XCTAssertFalse(none.todayComplete)

        let half = course(ticked([split[0]], daysAgo: 0), schedule: split)
        XCTAssertTrue(half.isTaken(split[0], on: today))
        XCTAssertFalse(half.isTaken(split[1], on: today))
        XCTAssertEqual(half.takenSlotCount(on: today), 1)
        XCTAssertEqual(half.nextSlot?.id, "pm")
        XCTAssertEqual(half.nextDoseMg, 30)
        XCTAssertTrue(half.loggedToday)
        XCTAssertFalse(half.todayComplete, "one of two doses isn't a finished day")

        let done = course(ticked(split, daysAgo: 0), schedule: split)
        XCTAssertTrue(done.todayComplete)
        XCTAssertNil(done.nextSlot)
        XCTAssertEqual(done.todayMg, 90)
    }

    func testTickingOutOfOrderLeavesTheEarlierDosePending() {
        let c = course(ticked([split[1]], daysAgo: 0), schedule: split)
        XCTAssertEqual(c.pendingSlots(on: today).map(\.id), ["am"])
        XCTAssertEqual(c.nextDoseMg, 60)
    }

    func testDayIsCompleteWhenThePlannedMgWasLoggedAnotherWay() {
        // 3 × 30 mg logged by hand instead of ticking the boxes.
        let manual = DoseEntry(id: "m", day: today, mgPerPill: 30, pillCount: 3)
        let c = course([manual], schedule: split)
        XCTAssertTrue(c.todayComplete)
        XCTAssertEqual(c.unscheduledEntries(on: today).map(\.id), ["m"])
    }

    func testEntriesForARemovedSlotCountAsUnscheduled() {
        let c = course(ticked(split, daysAgo: 0), schedule: [split[0]])
        XCTAssertEqual(c.unscheduledEntries(on: today).map(\.slotId), ["pm"])
        XCTAssertNil(c.slot(for: c.entries(on: today)[1]))
        XCTAssertEqual(c.todayMg, 90, "history keeps the dose either way")
    }

    func testWithoutAScheduleAnyDoseCompletesTheDay() {
        XCTAssertFalse(course(doses(daysAgo: [1])).todayComplete)
        XCTAssertTrue(course(doses(daysAgo: [0])).todayComplete)
        XCTAssertEqual(course(doses(daysAgo: [1])).nextDoseMg, 80)
    }

    func testHalfTickedTodayDoesNotDragThePaceDown() {
        let goal = profile(goalTotal: 450)
        let before = ticked(split, daysAgo: 2) + ticked(split, daysAgo: 1)

        let half = course(before + ticked([split[0]], daysAgo: 0), profile: goal, schedule: split)
        XCTAssertEqual(try XCTUnwrap(half.paceMgPerDay), 90, accuracy: 1e-9)
        // 240 mg in, 210 to go at 90 a day → 3 dosing days, today being the first.
        XCTAssertEqual(half.estimatedFinishDay, Day.adding(2, to: today))

        let done = course(before + ticked(split, daysAgo: 0), profile: goal, schedule: split)
        XCTAssertEqual(try XCTUnwrap(done.paceMgPerDay), 90, accuracy: 1e-9)
        XCTAssertEqual(done.estimatedFinishDay, Day.adding(2, to: today))
    }

    func testRefillDaysUseTheWholeSchedule() {
        // The last entry is a single pill, but a day is three.
        let c = course(ticked(split, daysAgo: 1), refill: RefillInfo(pillsLeft: 10, boxSize: 60), schedule: split)
        XCTAssertEqual(c.pillsPerDay, 3)
        XCTAssertEqual(c.refillDaysLeft, 3)
    }

    func testDailySeriesFillsGapsAndStartsFromPriorDose() {
        let c = course(doses(daysAgo: [3, 1]), profile: profile(prior: 100))
        XCTAssertEqual(c.dailySeries.map(\.cumulative), [180, 180, 260, 260])
        XCTAssertEqual(c.dailySeries.last?.day, today)
    }

    func testMilestones() {
        // Goal 400 mg, 120 mg/kg mark hidden because it's above the goal.
        let c = course(doses(daysAgo: [3, 2, 1]), profile: profile(goalTotal: 400))
        let byId = Dictionary(uniqueKeysWithValues: c.milestones.map { ($0.id, $0) })
        XCTAssertEqual(c.milestones.map(\.id), ["25", "50", "75", "goal"])
        XCTAssertEqual(byId["25"]?.state, .reached(Day.adding(-2, to: today)))
        XCTAssertEqual(byId["50"]?.state, .reached(Day.adding(-1, to: today)))
        XCTAssertEqual(byId["75"]?.state, .projected(today))
        XCTAssertEqual(byId["goal"]?.state, .projected(Day.adding(1, to: today)))
    }

    func testMilestonesIncludeLowMarkAndPriorDose() {
        let c = course(doses(daysAgo: [1]), profile: profile(prior: 3_000))
        XCTAssertEqual(c.milestones.map(\.id), ["25", "50", "75", "low", "goal"])
        XCTAssertEqual(c.milestones.first?.state, .reachedBeforeTracking)
    }

    func testMilestonesCrossedByADose() {
        let c = course([], profile: profile(goalTotal: 400))
        XCTAssertEqual(c.milestonesCrossed(from: 90, to: 210).map(\.id), ["25", "50"])
        XCTAssertEqual(c.milestonesCrossed(from: 320, to: 400).map(\.id), ["goal"])
        XCTAssertTrue(c.milestonesCrossed(from: 110, to: 190).isEmpty)
    }

    func testFormatting() {
        XCTAssertEqual(CourseSnapshot.trimmed(40), "40")
        XCTAssertEqual(CourseSnapshot.trimmed(37.5), "37.5")
        XCTAssertEqual(CourseSnapshot.doseLabel(mgPerPill: 40, pillCount: 2), "2 × 40 mg")
    }
}
