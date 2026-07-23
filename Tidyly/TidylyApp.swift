import SwiftUI
import SwiftData

@main
struct TidylyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(CloudShareAppDelegate.self) private var cloudShareAppDelegate
    @StateObject private var db = DatabaseService()
    @StateObject private var cloudAccount = CloudAccountService()
    @StateObject private var householdSharing = HouseholdSharingService()
    @StateObject private var cloudTaskSync = CloudTaskSyncService()
    @StateObject private var supabaseConnection = SupabaseConnectionService()
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
                    .environmentObject(cloudAccount)
                    .environmentObject(householdSharing)
                    .environmentObject(cloudTaskSync)
                    .environmentObject(supabaseConnection)
                    .tag(4)
            }
            .modelContainer(db.modelContainer)
            .tint(ColorAsset.primary.color)
            .preferredColorScheme(darkModeEnabled ? .dark : .light)
            .task {
                await configureNotificationsOnLaunch()
                await db.refreshWidgetSnapshot()
                await cloudAccount.refresh()
                cloudTaskSync.start(databaseService: db)
                await cloudTaskSync.syncNow()
            }
            .alert("Reminder Update Failed", isPresented: Binding(
                get: { db.notificationError != nil },
                set: { if !$0 { db.notificationError = nil } }
            )) {
                Button("OK", role: .cancel) { db.notificationError = nil }
            } message: {
                Text(db.notificationError ?? "Check notification permissions and try again.")
            }
            .onOpenURL { url in
                guard url.scheme == "tidyly" else { return }
                if url.host == "today" {
                    selectedTab = 0
                } else if url.host == "household-invite" {
                    supabaseConnection.handleInvitationURL(url)
                    selectedTab = 4
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                _Concurrency.Task { await cloudTaskSync.syncNow() }
            }
            .task { await supabaseConnection.restoreSession() }
        }
    }

    private func configureNotificationsOnLaunch() async {
        do {
            let settings = try await db.fetchSettings()
            guard settings.notificationsEnabled else {
                await NotificationService.disableAll()
                return
            }

            switch await NotificationService.permissionStatus() {
            case .notDetermined:
                let granted = try await NotificationService.requestPermission()
                if granted {
                    await db.refreshNotifications()
                } else {
                    try await db.updateSettings(
                        householdName: nil,
                        darkMode: nil,
                        notificationsEnabled: false,
                        weekStartsMonday: nil
                    )
                    await NotificationService.disableAll()
                }
            case .authorized:
                await db.refreshNotifications()
            case .denied:
                // Permission may persist across reinstalls. Keep launch quiet and
                // reflect the actual system state in Tidyly's reminder setting.
                try await db.updateSettings(
                    householdName: nil,
                    darkMode: nil,
                    notificationsEnabled: false,
                    weekStartsMonday: nil
                )
                await NotificationService.disableAll()
            }
        } catch {
            db.notificationError = error.localizedDescription
        }
    }
}
