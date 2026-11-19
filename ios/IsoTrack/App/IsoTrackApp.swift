import SwiftUI
import UserNotifications

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct IsoTrackApp: App {
    @State private var store: AppStore
    @State private var router = Router()
    private let notificationHandler: NotificationHandler
    @AppStorage("appearance") private var appearance: Appearance = .dark
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = LaunchMode.makeStore()
        _store = State(initialValue: store)
        notificationHandler = NotificationHandler(store: store)
        UNUserNotificationCenter.current().delegate = notificationHandler
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(appearance.colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    DispatchQueue.main.async { store.refresh() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Every change is saved as it happens, so there is nothing to
            // flush on the way out. On the way back in, re-read the file to
            // pick up doses logged from the widget or Siri.
            if phase == .active {
                store.refresh()
            }
        }
    }
}

/// Which tab is showing, so any screen can send the user to another one.
@Observable
final class Router {
    enum Tab: Hashable {
        case today, journey, care
    }

    var tab: Tab = .today

    init() {
        // "--tab journey" opens a specific tab (used for screenshots).
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--tab"), index + 1 < args.count {
            switch args[index + 1] {
            case "journey": tab = .journey
            case "care": tab = .care
            default: break
            }
        }
    }
}

/// Launch-argument switches used by UI tests and for previewing the app with
/// sample data. Both run against a throwaway file — never the real data.
/// `--demo-schedule` is the demo data plus a two-dose schedule.
enum LaunchMode {
    static var isUITest: Bool { CommandLine.arguments.contains("--uitest-reset") }
    static var isDemo: Bool { CommandLine.arguments.contains("--demo-data") || hasDemoSchedule }
    static var hasDemoSchedule: Bool { CommandLine.arguments.contains("--demo-schedule") }

    static func makeStore() -> AppStore {
        guard isUITest || isDemo else { return AppStore() }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("isotrack-sandbox.json")
        SharedStore.removeAll(at: url)
        if isDemo {
            SharedStore.write(DemoData.backup(withSchedule: hasDemoSchedule), to: url)
        }
        return AppStore(url: url, syncsSystem: false)
    }
}

/// A realistic mid-course data set for screenshots and previews.
enum DemoData {
    /// "60 mg with my first meal, 30 mg with my second."
    static let schedule = [
        DoseSlot(id: "s1", label: "First meal", mgPerPill: 30, pillCount: 2, reminderMinutes: 8 * 60),
        DoseSlot(id: "s2", label: "Second meal", mgPerPill: 30, pillCount: 1, reminderMinutes: nil),
    ]

    static func backup(today: String = Day.today, withSchedule: Bool = false) -> Backup {
        let profile = UserProfile(weightKg: 72.5, priorMg: 0, goalMgKg: 150,
                                  goalTotalMg: nil, startedDay: Day.adding(-96, to: today))
        var entries: [DoseEntry] = []
        let skipped: Set<Int> = [9, 31, 58, 77]
        for offset in stride(from: 96, through: 1, by: -1) where !skipped.contains(offset) {
            let strength: Double = offset > 60 ? 20 : 40
            entries.append(DoseEntry(id: "demo-\(offset)", day: Day.adding(-offset, to: today),
                                     mgPerPill: strength, pillCount: 2))
        }
        let appointments = [
            Appointment(id: "a1", day: Day.adding(-64, to: today), kind: .bloodDraw, attended: true),
            Appointment(id: "a2", day: Day.adding(-62, to: today), kind: .dermVisit, attended: true),
            Appointment(id: "a3", day: Day.adding(-33, to: today), kind: .bloodDraw, attended: true),
            Appointment(id: "a4", day: Day.adding(-31, to: today), kind: .dermVisit, attended: true),
            Appointment(id: "a5", day: Day.adding(-2, to: today), kind: .bloodDraw, attended: false),
            Appointment(id: "a6", day: Day.adding(3, to: today), kind: .dermVisit, attended: false),
        ]
        let checkIns = [
            CheckIn(id: "c1", day: Day.adding(-12, to: today),
                    symptoms: ["dryLips": 2, "drySkin": 1], note: nil),
            CheckIn(id: "c2", day: Day.adding(-6, to: today),
                    symptoms: ["dryLips": 3, "dryEyes": 1, "aches": 1],
                    note: "Lower back sore after the gym."),
            CheckIn(id: "c3", day: Day.adding(-1, to: today),
                    symptoms: ["dryLips": 2, "sunSensitivity": 1], note: nil),
        ]
        if withSchedule {
            // The last week was taken as split doses.
            for offset in 1...7 {
                let day = Day.adding(-offset, to: today)
                entries.removeAll { $0.day == day }
                entries += schedule.map {
                    DoseEntry(id: "demo-\(offset)-\($0.id)", day: day, mgPerPill: $0.mgPerPill,
                              pillCount: $0.pillCount, slotId: $0.id)
                }
            }
        }
        return Backup(profile: profile, entries: entries,
                      refill: RefillInfo(pillsLeft: 22, boxSize: 60),
                      appointments: appointments, checkIns: checkIns,
                      schedule: withSchedule ? schedule : [])
    }
}
