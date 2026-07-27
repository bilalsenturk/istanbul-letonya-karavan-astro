import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appNavigation: AppNavigation

    var body: some View {
        TabView(selection: $appNavigation.selectedTab) {
            DashboardView()
                .tabItem { Label("Panel", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(AppTab.dashboard)
            MapScreen()
                .tabItem { Label("Harita", systemImage: "map.fill") }
                .tag(AppTab.map)
            PlanScreen()
                .tabItem { Label("Plan", systemImage: "list.number") }
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
