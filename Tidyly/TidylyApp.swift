import SwiftUI
import SwiftData

@main
struct TidylyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var db = DatabaseService()
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
                    .environmentObject(supabaseConnection)
                    .tag(4)
            }
            .environmentObject(supabaseConnection)
            .modelContainer(db.modelContainer)
            .tint(ColorAsset.primary.color)
            .preferredColorScheme(darkModeEnabled ? .dark : .light)
            .task {
                await configureNotificationsOnLaunch()
                await db.refreshWidgetSnapshot()
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
                _Concurrency.Task { await supabaseConnection.refreshSharedData() }
            }
            .onChange(of: supabaseConnection.sharedDataLastLoadedAt) { _, loadedAt in
                guard loadedAt != nil else { return }
                do {
                    try db.applySupabaseSnapshot(
                        rooms: supabaseConnection.sharedRooms,
                        tasks: supabaseConnection.sharedTasks,
                        completions: supabaseConnection.sharedCompletions
                    )
                } catch {
                    db.notificationError = "Shared household data couldn’t be cached: \(error.localizedDescription)"
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .localCompletionCommitted)) { notification in
                guard let request = notification.object as? LocalCompletionSyncRequest else { return }
                _Concurrency.Task {
                    do {
                        try await supabaseConnection.syncCompletion(request)
                    } catch {
                        db.notificationError = "Completion saved locally but couldn’t sync: \(error.localizedDescription)"
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .localCompletionReversed)) { notification in
                guard let request = notification.object as? LocalCompletionReversalSyncRequest else { return }
                _Concurrency.Task {
                    do {
                        try await supabaseConnection.syncCompletionReversal(request)
                    } catch {
                        db.notificationError = "Completion reversal saved locally but couldn’t sync: \(error.localizedDescription)"
                    }
                }
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
