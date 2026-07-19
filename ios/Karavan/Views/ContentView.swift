import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Panel", systemImage: "gauge.with.dots.needle.67percent") }
            MapScreen()
                .tabItem { Label("Harita", systemImage: "map.fill") }
            PlanScreen()
                .tabItem { Label("Plan", systemImage: "list.number") }
        }
        .tint(Theme.c2)
    }
}
