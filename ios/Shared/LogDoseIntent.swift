import AppIntents
import Foundation

/// One-tap dose logging exposed to the widget button, Siri, and Shortcuts.
/// With a dose schedule it ticks off the next scheduled dose; without one it
/// logs the usual dose. (The type name is what saved shortcuts refer to —
/// keep it.)
struct LogUsualDoseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Dose"
    static var description = IntentDescription(
        "Logs your next scheduled isotretinoin dose for today, or your usual dose if you don't use a schedule."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch SharedDoseLogger.logNextDose() {
        case .unavailable:
            return .result(dialog: "Open IsoTrack and finish setting up first.")
        case .nothingDue:
            return .result(dialog: "All of today's doses are already logged.")
        case .logged(let result):
            let logged = CourseSnapshot.trimmed(result.totalMg)
            let total = Int(result.cumulativeMg.rounded())
            guard let label = result.slotLabel else {
                return .result(dialog: "Logged \(logged) mg — you're at \(total) mg total.")
            }
            let left = result.remainingSlots == 0
                ? "That's today done"
                : "\(result.remainingSlots) more to go today"
            return .result(dialog: "Logged \(logged) mg for \(label). \(left) — you're at \(total) mg total.")
        }
    }
}
