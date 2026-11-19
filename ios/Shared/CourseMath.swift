import Foundation

/// Every number the app shows, derived from the stored data for a given
/// "today". Pure value type so the app, the widget, and the tests all compute
/// the same thing.
struct CourseSnapshot {
    let profile: UserProfile?
    /// Sorted by day, oldest first.
    let entries: [DoseEntry]
    let refill: RefillInfo?
    /// The planned doses for each day, in the order they're taken. Empty
    /// when the user logs one "usual" dose a day instead.
    let schedule: [DoseSlot]
    let today: String

    /// The 120 mg/kg mark that's commonly quoted as the low end of the
    /// cumulative-dose range. Shown as a reference marker only.
    static let lowMarkMgPerKg = 120.0
    /// How many recent days feed the pace and the finish estimate.
    static let paceWindowDays = 14

    init(profile: UserProfile?, entries: [DoseEntry], refill: RefillInfo? = nil,
         schedule: [DoseSlot] = [], today: String = Day.today) {
        self.profile = profile
        self.entries = entries.sorted { $0.day < $1.day }
        self.refill = refill
        self.schedule = schedule
        self.today = today
    }

    init(backup: Backup, today: String = Day.today) {
        self.init(profile: backup.domainProfile, entries: backup.domainEntries,
                  refill: backup.refill, schedule: backup.domainSchedule, today: today)
    }

    // MARK: Totals

    var priorMg: Double { profile?.priorMg ?? 0 }

    var loggedMg: Double { entries.reduce(0) { $0 + $1.totalMg } }

    var cumulativeMg: Double { priorMg + loggedMg }

    var goalMg: Double {
        guard let p = profile else { return 0 }
        if let total = p.goalTotalMg, total > 0 { return total }
        return p.goalMgKg * p.weightKg
    }

    /// Goal expressed as mg/kg (derived, so it's correct for custom totals too).
    var goalMgPerKg: Double {
        guard let p = profile, p.weightKg > 0 else { return 0 }
        return goalMg / p.weightKg
    }

    var lowMarkMg: Double {
        guard let p = profile else { return 0 }
        return Self.lowMarkMgPerKg * p.weightKg
    }

    var remainingMg: Double { max(0, goalMg - cumulativeMg) }

    var progress: Double {
        goalMg > 0 ? min(1, cumulativeMg / goalMg) : 0
    }

    var mgPerKg: Double {
        guard let p = profile, p.weightKg > 0 else { return 0 }
        return cumulativeMg / p.weightKg
    }

    var goalReached: Bool { goalMg > 0 && cumulativeMg >= goalMg }

    // MARK: Days

    var mgByDay: [String: Double] {
        var result: [String: Double] = [:]
        for entry in entries { result[entry.day, default: 0] += entry.totalMg }
        return result
    }

    var loggedDays: Set<String> { Set(entries.map(\.day)) }

    var firstDay: String? { entries.first?.day }

    var todayMg: Double { mg(on: today) }

    var loggedToday: Bool { todayMg > 0 }

    var yesterday: String { Day.adding(-1, to: today) }

    func mg(on day: String) -> Double {
        entries.reduce(0) { $1.day == day ? $0 + $1.totalMg : $0 }
    }

    func entries(on day: String) -> [DoseEntry] {
        entries.filter { $0.day == day }
    }

    /// True when the course started before yesterday and yesterday has no entry.
    var yesterdayMissed: Bool {
        guard let firstDay, firstDay < yesterday else { return false }
        return !loggedDays.contains(yesterday)
    }

    /// The most recently logged strength × count, used for one-tap logging.
    var usualDose: (mgPerPill: Double, pillCount: Int) {
        if let last = entries.last { return (last.mgPerPill, last.pillCount) }
        return (40, 1)
    }

    var usualTotalMg: Double { usualDose.mgPerPill * Double(usualDose.pillCount) }

    // MARK: Schedule

    var hasSchedule: Bool { !schedule.isEmpty }

    /// Planned mg per day across every scheduled dose.
    var scheduledMg: Double { schedule.reduce(0) { $0 + $1.totalMg } }

    var scheduledPills: Int { schedule.reduce(0) { $0 + $1.pillCount } }

    /// The entry that ticked `slot` off on `day`, if it has been taken.
    func entry(for slot: DoseSlot, on day: String) -> DoseEntry? {
        entries.first { $0.day == day && $0.slotId == slot.id }
    }

    func isTaken(_ slot: DoseSlot, on day: String) -> Bool {
        entry(for: slot, on: day) != nil
    }

    /// Scheduled doses not yet ticked off on `day`, in schedule order.
    func pendingSlots(on day: String) -> [DoseSlot] {
        let taken = Set(entries.lazy.filter { $0.day == day }.compactMap(\.slotId))
        return schedule.filter { !taken.contains($0.id) }
    }

    func takenSlotCount(on day: String) -> Int {
        schedule.count - pendingSlots(on: day).count
    }

    /// The scheduled dose an entry belongs to, if that slot still exists.
    func slot(for entry: DoseEntry) -> DoseSlot? {
        guard let id = entry.slotId else { return nil }
        return schedule.first { $0.id == id }
    }

    /// Doses on `day` logged outside the schedule (or for a slot since removed).
    func unscheduledEntries(on day: String) -> [DoseEntry] {
        entries.filter { $0.day == day && slot(for: $0) == nil }
    }

    /// The next scheduled dose still to take today.
    var nextSlot: DoseSlot? { pendingSlots(on: today).first }

    /// True when every scheduled dose on `day` is ticked off, or the day's
    /// planned mg was reached some other way. Without a schedule, any dose.
    func isComplete(on day: String) -> Bool {
        guard hasSchedule else { return mg(on: day) > 0 }
        return pendingSlots(on: day).isEmpty || mg(on: day) >= scheduledMg - 0.001
    }

    /// Today's dosing is finished: nothing more to log or be reminded about.
    var todayComplete: Bool { isComplete(on: today) }

    /// What one tap logs next: the next scheduled dose, else the usual dose.
    var nextDose: (mgPerPill: Double, pillCount: Int) {
        if let slot = nextSlot { return (slot.mgPerPill, slot.pillCount) }
        return usualDose
    }

    var nextDoseMg: Double { nextDose.mgPerPill * Double(nextDose.pillCount) }

    /// Pills taken on a normal day: the whole schedule, else the usual dose.
    var pillsPerDay: Int { hasSchedule ? scheduledPills : usualDose.pillCount }

    /// Consecutive logged days ending today (or yesterday if today isn't logged yet).
    var streakDays: Int {
        let logged = loggedDays
        guard !logged.isEmpty else { return 0 }
        var cursor = logged.contains(today) ? today : yesterday
        var streak = 0
        while logged.contains(cursor) {
            streak += 1
            cursor = Day.adding(-1, to: cursor)
        }
        return streak
    }

    /// The last day that counts as "over": today once it's fully logged
    /// (every scheduled dose, when there's a schedule), otherwise yesterday.
    private var lastSettledDay: String { todayComplete ? today : yesterday }

    /// Days from the first logged dose through the last settled day.
    var trackedDayCount: Int {
        guard let firstDay, firstDay <= lastSettledDay else { return 0 }
        return Day.distance(from: firstDay, to: lastSettledDay) + 1
    }

    /// Share of tracked days that have a dose logged, 0...1.
    var adherence: Double? {
        let total = trackedDayCount
        guard total > 0, let firstDay else { return nil }
        let end = lastSettledDay
        let logged = loggedDays.filter { $0 >= firstDay && $0 <= end }.count
        return Double(logged) / Double(total)
    }

    // MARK: Pace and projection

    /// Average mg per calendar day over the most recent window (up to 14
    /// days, never reaching back before the first dose). Missed days count as
    /// zero so the finish estimate stays honest; today only counts once it's
    /// complete, so a half-ticked schedule doesn't drag the pace down.
    var paceMgPerDay: Double? {
        guard let firstDay else { return nil }
        let end = lastSettledDay
        guard firstDay <= end else { return nil }
        let earliest = Day.adding(-(Self.paceWindowDays - 1), to: end)
        let start = max(firstDay, earliest)
        let days = Day.distance(from: start, to: end) + 1
        guard days > 0 else { return nil }
        let total = entries.reduce(0.0) { $1.day >= start && $1.day <= end ? $0 + $1.totalMg : $0 }
        return total > 0 ? total / Double(days) : nil
    }

    /// Dosing days still needed at the current pace.
    var daysRemaining: Int? {
        guard !goalReached, goalMg > 0, let pace = paceMgPerDay, pace > 0 else { return nil }
        return Int((remainingMg / pace).rounded(.up))
    }

    var estimatedFinishDay: String? {
        guard let days = daysRemaining else { return nil }
        // If today isn't finished yet, today is the first of the remaining days.
        return Day.adding(todayComplete ? days : days - 1, to: today)
    }

    var estimatedFinish: Date? { estimatedFinishDay.map(Day.date(from:)) }

    /// Days from today until the estimated finish.
    var daysUntilFinish: Int? {
        estimatedFinishDay.map { Day.distance(from: today, to: $0) }
    }

    // MARK: Refill

    /// Whole days of pills remaining at the usual dose (or the full schedule),
    /// when refill tracking is on.
    var refillDaysLeft: Int? {
        guard let refill else { return nil }
        return refill.pillsLeft / max(1, pillsPerDay)
    }

    var refillIsLow: Bool { (refillDaysLeft ?? .max) <= 5 }

    // MARK: Series

    struct SeriesPoint: Identifiable, Equatable {
        var id: String { day }
        var day: String
        var date: Date
        var cumulative: Double
    }

    /// Daily cumulative series from the first entry through today
    /// (or through the last entry if one is dated in the future).
    var dailySeries: [SeriesPoint] {
        guard let firstDay, let lastDay = entries.last?.day else { return [] }
        let byDay = mgByDay
        let endDay = max(lastDay, today)
        var points: [SeriesPoint] = []
        var running = priorMg
        var cursor = firstDay
        // Guard against a wildly mis-dated entry producing a huge series.
        var budget = 3660
        while cursor <= endDay, budget > 0 {
            running += byDay[cursor] ?? 0
            points.append(SeriesPoint(day: cursor, date: Day.date(from: cursor), cumulative: running))
            cursor = Day.adding(1, to: cursor)
            budget -= 1
        }
        return points
    }

    // MARK: Milestones

    struct Milestone: Identifiable, Equatable {
        enum State: Equatable {
            /// Crossed on this day.
            case reached(String)
            /// Already past this point when tracking began.
            case reachedBeforeTracking
            /// Expected on this day at the current pace.
            case projected(String)
            case pending
        }

        var id: String
        var title: String
        var detail: String
        var targetMg: Double
        var state: State

        var isReached: Bool {
            switch state {
            case .reached, .reachedBeforeTracking: return true
            case .projected, .pending: return false
            }
        }
    }

    var milestones: [Milestone] {
        guard goalMg > 0 else { return [] }
        var targets: [(id: String, title: String, mg: Double)] = [
            ("25", "Quarter of the way", goalMg * 0.25),
            ("50", "Halfway", goalMg * 0.5),
            ("75", "Three quarters", goalMg * 0.75),
        ]
        if lowMarkMg > 0, lowMarkMg < goalMg - 0.5 {
            targets.append(("low", "120 mg/kg mark", lowMarkMg))
        }
        targets.append(("goal", "Goal reached", goalMg))
        targets.sort { $0.mg < $1.mg }

        let series = dailySeries
        let pace = paceMgPerDay
        return targets.map { target in
            let state: Milestone.State
            if priorMg >= target.mg {
                state = .reachedBeforeTracking
            } else if let hit = series.first(where: { $0.cumulative >= target.mg && $0.day <= today }) {
                state = .reached(hit.day)
            } else if cumulativeMg >= target.mg {
                // Only reachable through a future-dated entry.
                state = .reached(today)
            } else if let pace, pace > 0 {
                let days = Int(((target.mg - cumulativeMg) / pace).rounded(.up))
                state = .projected(Day.adding(todayComplete ? days : days - 1, to: today))
            } else {
                state = .pending
            }
            return Milestone(id: target.id, title: target.title,
                             detail: "\(Self.whole(target.mg)) mg", targetMg: target.mg, state: state)
        }
    }

    /// The milestones (by id) that a change from `before` to `after` mg crossed.
    func milestonesCrossed(from before: Double, to after: Double) -> [Milestone] {
        milestones.filter { before < $0.targetMg && after >= $0.targetMg }
    }

    // MARK: Formatting

    /// "1,200" — whole number with grouping.
    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// "40" or "37.5" — trims a pointless ".0".
    static func trimmed(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "2 × 40 mg"
    static func doseLabel(mgPerPill: Double, pillCount: Int) -> String {
        "\(pillCount) × \(trimmed(mgPerPill)) mg"
    }
}
