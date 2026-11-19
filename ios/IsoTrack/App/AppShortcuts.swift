import AppIntents

struct IsoTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogUsualDoseIntent(),
            phrases: [
                "Log my dose in \(.applicationName)",
                "Log my \(.applicationName) dose",
                "I took my \(.applicationName) pill"
            ],
            shortTitle: "Log dose",
            systemImageName: "pills.fill"
        )
    }
}
