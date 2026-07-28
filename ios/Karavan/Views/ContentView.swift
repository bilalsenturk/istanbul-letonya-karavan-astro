import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appNavigation: AppNavigation
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore

    var body: some View {
        Group {
            if account.isRestoring || !account.isSignedIn {
                kuzeyTabs
            } else if workspace.selectedTrip == nil {
                TripsHomeView()
            } else if workspace.selectedTrip?.kind == .kuzey2026 {
                kuzeyTabs
            } else {
                AccountStopsView()
            }
        }
    }

    private var kuzeyTabs: some View {
        TabView(selection: $appNavigation.selectedTab) {
            DashboardView()
                .tabItem { Label("Panel", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(AppTab.dashboard)
            PlanScreen()
                .tabItem { Label("Plan", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.plan)
            JournalView()
                .tabItem { Label("Günlük", systemImage: "book.closed.fill") }
                .tag(AppTab.journal)
            ToolsView()
                .tabItem { Label("Araçlar", systemImage: "wrench.and.screwdriver.fill") }
                .tag(AppTab.tools)
        }
        .tint(Theme.c2)
    }
}
