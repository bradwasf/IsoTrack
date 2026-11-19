import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var banner: AppStore.Celebration?

    var body: some View {
        ZStack {
            if store.profile == nil {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }

            ConfettiView(trigger: store.confettiTrigger, big: store.celebration != nil)
        }
        .overlay(alignment: .top) {
            if let banner {
                CelebrationBanner(celebration: banner)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { dismissBanner() }
            }
        }
        .tint(.brand)
        .animation(.smooth(duration: 0.45), value: store.profile == nil)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: banner)
        .sensoryFeedback(.success, trigger: store.logPulse)
        .onChange(of: store.celebration) { _, celebration in
            guard let celebration else { return }
            banner = celebration
            Task {
                try? await Task.sleep(for: .seconds(4))
                if banner == celebration { dismissBanner() }
            }
        }
    }

    private func dismissBanner() {
        banner = nil
        store.dismissCelebration()
    }
}

/// The main shell. A bottom tab bar on a compact iPhone; on iPhone Duo's
/// inner display the system moves the same tabs to where they fit best.
struct MainTabs: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "pills.fill", value: Router.Tab.today) {
                TodayView()
            }
            Tab("Journey", systemImage: "chart.xyaxis.line", value: Router.Tab.journey) {
                JourneyView()
            }
            Tab("Care", systemImage: "stethoscope", value: Router.Tab.care) {
                CareView()
            }
            .badge(store.overdueAppointments.count)
        }
    }
}

// MARK: - Settings entry point

private struct SettingsToolbar: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
    }
}

extension View {
    /// Adds the gear button that opens Settings.
    func settingsToolbar() -> some View {
        modifier(SettingsToolbar())
    }

    /// The standard chrome for a top-level tab screen.
    func tabScreen(_ title: String) -> some View {
        self
            .background { AppBackground() }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .settingsToolbar()
    }
}
