import SwiftUI
import SwiftData

@main
struct TidylyApp: App {
    @StateObject private var db = DatabaseService()
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                TodayScreen()
                    .tabItem {
                        Label("Today", systemImage: "checklist")
                    }
                    .environmentObject(db)
                    .tag(0)

                RoomsScreen()
                    .tabItem {
                        Label("Rooms", systemImage: "square.grid.2x2")
                    }
                    .environmentObject(db)
                    .tag(1)

                ScheduleScreen()
                    .tabItem {
                        Label("Schedule", systemImage: "calendar")
                    }
                    .environmentObject(db)
                    .tag(2)

                StatsScreen()
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar.fill")
                    }
                    .environmentObject(db)
                    .tag(3)

                SettingsScreen()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .environmentObject(db)
                    .tag(4)
            }
            .modelContainer(db.modelContainer)
            .tint(ColorAsset.primary.color)
            .preferredColorScheme(darkModeEnabled ? .dark : .light)
            .task { await db.refreshWidgetSnapshot() }
            .alert("Reminder Update Failed", isPresented: Binding(
                get: { db.notificationError != nil },
                set: { if !$0 { db.notificationError = nil } }
            )) {
                Button("OK", role: .cancel) { db.notificationError = nil }
            } message: {
                Text(db.notificationError ?? "Check notification permissions and try again.")
            }
            .onOpenURL { url in
                if url.scheme == "tidyly", url.host == "today" { selectedTab = 0 }
            }
        }
    }
}
