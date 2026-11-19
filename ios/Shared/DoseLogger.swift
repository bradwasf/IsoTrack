import Foundation
import WidgetKit

/// File-based dose logging used by the widget's App Intent (and Siri), which
/// run outside the app process. Mirrors `AppStore.logNextDose`: appends the
/// next scheduled dose (or the user's usual dose when there's no schedule),
/// decrements the refill count, and persists.
enum SharedDoseLogger {
    struct LogResult: Equatable {
        var totalMg: Double
        var cumulativeMg: Double
        /// The scheduled dose that was ticked off, when there's a schedule.
        var slotLabel: String?
        /// Scheduled doses still to take that day after this one.
        var remainingSlots: Int = 0
    }

    enum Outcome: Equatable {
        case logged(LogResult)
        /// Every scheduled dose for the day is already ticked off.
        case nothingDue
        /// No course yet, or the data file couldn't be read or written.
        case unavailable

        var result: LogResult? {
            if case .logged(let result) = self { return result }
            return nil
        }
    }

    @discardableResult
    static func logNextDose(at url: URL = SharedStore.dataURL,
                            day: String = Day.today,
                            reloadWidgets: Bool = true) -> Outcome {
        guard var backup = SharedStore.loadBackup(at: url), let profile = backup.profile else {
            return .unavailable
        }

        let course = CourseSnapshot(backup: backup, today: day)
        let slot = course.pendingSlots(on: day).first
        if course.hasSchedule, slot == nil { return .nothingDue }

        let mg = slot?.mgPerPill ?? course.usualDose.mgPerPill
        let pills = slot?.pillCount ?? course.usualDose.pillCount

        backup.entries.append(Backup.StoredEntry(
            id: UUID().uuidString, date: day, mg: mg, pills: pills, slot: slot?.id
        ))
        backup.entries.sort { $0.date < $1.date }

        if var refill = backup.refill {
            refill.pillsLeft = max(0, refill.pillsLeft - pills)
            backup.refill = refill
        }

        guard SharedStore.write(backup, to: url) else { return .unavailable }

        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }

        let cumulative = profile.priorMg + backup.entries.reduce(0) { $0 + $1.mg * Double($1.pills) }
        return .logged(LogResult(
            totalMg: mg * Double(pills),
            cumulativeMg: cumulative,
            slotLabel: slot?.label,
            remainingSlots: slot == nil ? 0 : course.pendingSlots(on: day).count - 1
        ))
    }
}
