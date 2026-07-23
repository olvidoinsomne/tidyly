import CloudKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject var db: DatabaseService
    @EnvironmentObject var cloudAccount: CloudAccountService
    @EnvironmentObject var householdSharing: HouseholdSharingService
    @EnvironmentObject var cloudTaskSync: CloudTaskSyncService
    @EnvironmentObject var supabaseConnection: SupabaseConnectionService
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("weekStartsMonday") private var weekStartsMonday = true
    @State private var settings: Settings?
    @State private var loading = true
    @State private var refreshing = false
    @State private var editingName = false
    @State private var householdName = ""
    @State private var showClearConfirm = false
    @State private var notificationError: String?
    @State private var defaultReminderTime = Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
    @State private var overdueFollowUpsEnabled = false
    @State private var permissionStatus: NotificationPermissionStatus = .notDetermined
    @State private var showingHouseholdShare = false
    @State private var exportDocument: TidylyBackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImport: TidylyBackup?
    @State private var showingImportConfirmation = false
    @State private var dataTransferStatus: String?
    @State private var householdSharingError: String?
    @State private var showingSupabaseJoinConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingXl) {
                    // Household
                    SettingsSection(title: "Household") {
                        VStack(spacing: AppTheme.spacingMd) {
                        HStack {
                            SettingIcon(icon: "house.fill", color: ColorAsset.primary.color)
                            VStack(alignment: .leading) {
                                Text("Household Name")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ColorAsset.text.color)
                                if editingName {
                                    HStack {
                                        TextField("My Home", text: $householdName)
                                            .textFieldStyle(.roundedBorder)
                                        Button {
                                            _Concurrency.Task { await saveName() }
                                        } label: {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.white)
                                                .frame(width: 36, height: 36)
                                                .background(ColorAsset.primary.color)
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    Text(settings?.householdName ?? "My Home")
                                        .font(.system(size: 13))
                                        .foregroundColor(ColorAsset.textTertiary.color)
                                }
                            }
                            Spacer()
                            if !editingName {
                                Button("Edit") { editingName = true }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(ColorAsset.primary.color)
                            }
                        }
                        Divider()
                        HStack(alignment: .top, spacing: AppTheme.spacingMd) {
                            Image(systemName: cloudAccount.status.isAvailable ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                                .foregroundColor(cloudAccount.status.isAvailable ? ColorAsset.success.color : ColorAsset.warning.color)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cloudAccount.status.title)
                                    .font(.body.weight(.semibold))
                                Text(cloudAccount.status.guidance)
                                    .font(.footnote)
                                    .foregroundColor(ColorAsset.textTertiary.color)
                            }
                            Spacer()
                            if !cloudAccount.status.isAvailable && cloudAccount.status != .checking {
                                Button("Retry") { _Concurrency.Task { await cloudAccount.refresh() } }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        Divider()
                        Button {
                            _Concurrency.Task {
                                await householdSharing.prepareHousehold(named: settings?.householdName ?? "My Home")
                                await cloudTaskSync.syncNow()
                                showingHouseholdShare = householdSharing.share != nil
                            }
                        } label: {
                            HStack {
                                SettingIcon(icon: "person.badge.plus", color: ColorAsset.primary.color)
                                VStack(alignment: .leading) {
                                    Text("Invite People")
                                        .font(.body.weight(.semibold))
                                    Text(householdSharing.statusText)
                                        .font(.footnote)
                                        .foregroundColor(ColorAsset.textTertiary.color)
                                }
                                Spacer()
                                if householdSharing.state == .preparing { ProgressView() }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!cloudAccount.status.isAvailable || householdSharing.state == .preparing)
                        Divider()
                        HStack {
                            SettingIcon(icon: "arrow.triangle.2.circlepath.icloud", color: ColorAsset.secondary.color)
                            VStack(alignment: .leading) {
                                Text("Shared Task Sync").font(.body.weight(.semibold))
                                Text(cloudTaskSync.statusText).font(.footnote).foregroundColor(ColorAsset.textTertiary.color)
                            }
                            Spacer()
                            Button(cloudTaskSync.state == .syncing ? "Syncing…" : "Sync Now") { _Concurrency.Task { await cloudTaskSync.syncNow() } }
                                .disabled(cloudTaskSync.state == .syncing)
                        }
                        }
                    }

                    sharedHouseholdSection

                    // Preferences
                    SettingsSection(title: "Preferences") {
                        VStack(spacing: 0) {
                            ToggleRow(icon: "bell.fill", color: ColorAsset.warning.color, label: "Notifications", isOn: Binding(
                                get: { settings?.notificationsEnabled ?? true },
                                set: { newValue in
                                    _Concurrency.Task { await toggleSetting("notifications_enabled", newValue) }
                                }
                            ))
                            Divider().padding(.leading, 56)
                            ToggleRow(icon: "moon.fill", color: ColorAsset.primary.color, label: "Dark Mode", isOn: Binding(
                                get: { settings?.darkMode ?? false },
                                set: { newValue in
                                    _Concurrency.Task { await toggleSetting("dark_mode", newValue) }
                                }
                            ))
                            Divider().padding(.leading, 56)
                            ToggleRow(icon: "calendar", color: ColorAsset.secondary.color, label: "Week Starts Monday", isOn: Binding(
                                get: { settings?.weekStartsMonday ?? true },
                                set: { newValue in
                                    _Concurrency.Task { await toggleSetting("week_starts_monday", newValue) }
                                }
                            ))
                        }
                    }

                    SettingsSection(title: "Reminders") {
                        VStack(spacing: AppTheme.spacingMd) {
                            DatePicker("Default reminder time", selection: $defaultReminderTime, displayedComponents: .hourAndMinute)
                                .disabled(settings?.notificationsEnabled != true)
                                .onChange(of: defaultReminderTime) { _, _ in _Concurrency.Task { await saveReminderSettings() } }
                            Divider()
                            Toggle("Overdue follow-up", isOn: $overdueFollowUpsEnabled)
                                .disabled(settings?.notificationsEnabled != true)
                                .onChange(of: overdueFollowUpsEnabled) { _, _ in _Concurrency.Task { await saveReminderSettings() } }
                            HStack {
                                Image(systemName: permissionStatus == .authorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                Text(permissionLabel)
                            }
                            .font(.footnote)
                            .foregroundColor(permissionStatus == .authorized ? ColorAsset.success.color : ColorAsset.warning.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Data
                    SettingsSection(title: "Data") {
                        VStack(spacing: 0) {
                            NavigationLink {
                                ActivityScreen()
                                    .environmentObject(db)
                            } label: {
                                HStack {
                                    SettingIcon(icon: "clock.arrow.circlepath", color: ColorAsset.primary.color)
                                    Text("Activity")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(ColorAsset.text.color)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(ColorAsset.textTertiary.color)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Activity history")
                            Divider().padding(.leading, 56)
                            ButtonRow(icon: "square.and.arrow.down", color: ColorAsset.secondary.color, label: "Export Data") {
                                _Concurrency.Task { await exportData() }
                            }
                            Divider().padding(.leading, 56)
                            ButtonRow(icon: "square.and.arrow.up", color: ColorAsset.primary.color, label: "Import Data") {
                                showingImporter = true
                            }
                            Divider().padding(.leading, 56)
                            if let dataTransferStatus {
                                Text(dataTransferStatus)
                                    .font(.footnote)
                                    .foregroundColor(ColorAsset.textSecondary.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, AppTheme.spacingSm)
                                    .accessibilityLabel(dataTransferStatus)
                                Divider().padding(.leading, 56)
                            }
                            ButtonRow(icon: "trash", color: ColorAsset.error.color, label: "Clear All Data", labelColor: ColorAsset.error.color) {
                                showClearConfirm = true
                            }
                        }
                    }

                    // About
                    SettingsSection(title: "About") {
                        HStack {
                            SettingIcon(icon: "info.circle.fill", color: ColorAsset.textSecondary.color)
                            VStack(alignment: .leading) {
                                Text("Version")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ColorAsset.text.color)
                                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                                    .font(.system(size: 13))
                                    .foregroundColor(ColorAsset.textTertiary.color)
                            }
                            Spacer()
                        }
                    }

                    Text("Tidyly · Made with care")
                        .font(.system(size: 13))
                        .foregroundColor(ColorAsset.textTertiary.color)

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, AppTheme.spacingXl)
            }
            .navigationTitle("Settings")
            .background(ColorAsset.background.color.ignoresSafeArea())
            .refreshable { await loadData() }
            .alert("Clear All Data", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    // Requires manual database access
                }
            } message: {
                Text("This will permanently delete all rooms, tasks, and completion history. This cannot be undone.")
            }
            .alert("Notifications Aren’t Enabled", isPresented: Binding(
                get: { notificationError != nil },
                set: { if !$0 { notificationError = nil } }
            )) {
                Button("OK", role: .cancel) { notificationError = nil }
            } message: {
                Text(notificationError ?? "Allow notifications in the Settings app and try again.")
            }
            .alert("Household Sharing Failed", isPresented: Binding(
                get: { householdSharingError != nil },
                set: { if !$0 { householdSharingError = nil } }
            )) {
                Button("OK", role: .cancel) { householdSharingError = nil }
            } message: {
                Text(householdSharingError ?? "Please try again.")
            }
            .alert("Join Shared Household?", isPresented: $showingSupabaseJoinConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Join and Clear Local Data", role: .destructive) {
                    _Concurrency.Task { await joinSupabaseHousehold() }
                }
            } message: {
                Text("Joining first adds your account to the shared household. Tidyly will then permanently clear this device’s existing rooms, tasks, completions, and activity. Export a backup before continuing if you may need this data.")
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .householdShareFailed)) { notification in
            let error = notification.object as? Error
            householdSharingError = error?.localizedDescription ?? "CloudKit couldn’t update this household share."
            #if DEBUG
            print("[CloudKitShare] controller failure: \(error?.localizedDescription ?? "unknown error")")
            #endif
        }
        .sheet(isPresented: $showingHouseholdShare) {
            if let share = householdSharing.share {
                CloudSharingView(
                    share: share,
                    container: CKContainer(identifier: CloudAccountService.containerIdentifier)
                )
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                dataTransferStatus = "Backup saved successfully."
            case .failure(let error):
                dataTransferStatus = "Export failed: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .confirmationDialog(
            "Replace Local Data?",
            isPresented: $showingImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import and Replace", role: .destructive) {
                _Concurrency.Task { await performImport() }
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Importing replaces this device’s rooms, tasks, completions, activity, and settings with the selected backup. This cannot be undone.")
        }
    }

    private var supabaseHouseholdIcon: String {
        switch supabaseConnection.state {
        case .loading, .authenticating: "person.crop.circle.badge.clock"
        case .signedOut: "person.crop.circle.badge.plus"
        case .needsHousehold: "house.badge.plus"
        case .ready: "house.and.flag.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var supabaseHouseholdColor: Color {
        switch supabaseConnection.state {
        case .loading, .authenticating, .signedOut: ColorAsset.primary.color
        case .needsHousehold: ColorAsset.secondary.color
        case .ready: ColorAsset.success.color
        case .failed: ColorAsset.warning.color
        }
    }

    private var supabaseHouseholdTitle: String {
        switch supabaseConnection.state {
        case .loading: "Loading Shared Household"
        case .signedOut: "Set Up Household Sharing"
        case .authenticating: "Signing In"
        case .needsHousehold: "Create Your Shared Household"
        case .ready(let household): household.name
        case .failed: "Household Setup Needs Attention"
        }
    }

    private var sharedHouseholdSection: some View {
        SettingsSection(title: "Shared Household") {
            VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
                sharedHouseholdStatus
                sharedHouseholdAction
                Text("Your existing rooms and tasks stay on this device until you explicitly choose to migrate them.")
                    .font(.caption)
                    .foregroundColor(ColorAsset.textTertiary.color)
            }
        }
    }

    private var sharedHouseholdStatus: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingMd) {
            SettingIcon(icon: supabaseHouseholdIcon, color: supabaseHouseholdColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(supabaseHouseholdTitle)
                    .font(.body.weight(.semibold))
                Text(supabaseConnection.statusText)
                    .font(.footnote)
                    .foregroundColor(ColorAsset.textTertiary.color)
            }
            Spacer()
            if supabaseConnection.isBusy { ProgressView() }
        }
    }

    @ViewBuilder
    private var sharedHouseholdAction: some View {
        if supabaseConnection.pendingInvitationToken != nil {
            pendingInvitationAction
        } else {
            sharedHouseholdStateAction
        }
    }

    @ViewBuilder
    private var sharedHouseholdStateAction: some View {
        switch supabaseConnection.state {
        case .signedOut:
            Button {
                supabaseConnection.startAppleSignIn()
            } label: {
                HStack {
                    Image(systemName: "apple.logo")
                    Text("Continue with Apple")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.black)
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerMd))
        case .needsHousehold:
            Button {
                _Concurrency.Task {
                    await supabaseConnection.createHousehold(
                        named: settings?.householdName ?? "My Home",
                        weekStartsMonday: settings?.weekStartsMonday ?? true
                    )
                }
            } label: {
                Label("Create Shared Household", systemImage: "house.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .ready:
            VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
                HStack {
                    Label("Supabase sharing active", systemImage: "checkmark.shield.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorAsset.success.color)
                    Spacer()
                    Button("Sign Out", role: .destructive) { supabaseConnection.signOut() }
                        .font(.footnote.weight(.semibold))
                }
                if let invitationURL = supabaseConnection.invitationURL {
                    ShareLink(
                        item: invitationURL,
                        subject: Text("Join my Tidyly household"),
                        message: Text("Use this link to join my shared household in Tidyly.")
                    ) {
                        Label("Share Invitation", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if let expiresAt = supabaseConnection.invitationExpiresAt {
                        Text("This link expires \(expiresAt.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption)
                            .foregroundColor(ColorAsset.textTertiary.color)
                    }
                    Button("Create a New Link") {
                        supabaseConnection.clearCreatedInvitation()
                        _Concurrency.Task { await supabaseConnection.createInvitation() }
                    }
                    .font(.footnote.weight(.semibold))
                } else {
                    Button {
                        _Concurrency.Task { await supabaseConnection.createInvitation() }
                    } label: {
                        Label("Create Invitation Link", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .failed:
            HStack {
                Button("Retry") { _Concurrency.Task { await supabaseConnection.retry() } }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Sign Out", role: .destructive) { supabaseConnection.signOut() }
            }
        case .loading, .authenticating:
            EmptyView()
        }
    }

    private var pendingInvitationAction: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
            Label("Household invitation received", systemImage: "envelope.badge.fill")
                .font(.footnote.weight(.semibold))
                .foregroundColor(ColorAsset.primary.color)
            Text("Back up any local rooms and tasks before joining. They cannot be merged into the shared household yet.")
                .font(.footnote)
                .foregroundColor(ColorAsset.textTertiary.color)
            HStack {
                Button("Export Backup") {
                    _Concurrency.Task { await exportData() }
                }
                .buttonStyle(.bordered)
                Spacer()
                if case .signedOut = supabaseConnection.state {
                    Button("Sign In First") { supabaseConnection.startAppleSignIn() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Review and Join") {
                        showingSupabaseJoinConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Button("Decline") { supabaseConnection.cancelPendingInvitation() }
                .font(.footnote)
        }
    }

    private func joinSupabaseHousehold() async {
        do {
            try await supabaseConnection.acceptPendingInvitation()
            try db.clearLocalHouseholdContentForSupabaseJoin()
            dataTransferStatus = "Joined the shared household. Local household data was cleared after acceptance."
        } catch {
            householdSharingError = "Couldn’t join the Supabase household: \(error.localizedDescription)"
        }
    }

    private func loadData() async {
        do {
            settings = try await db.fetchSettings()
            if let settings {
                defaultReminderTime = Calendar.current.date(from: DateComponents(hour: settings.defaultReminderHour, minute: settings.defaultReminderMinute)) ?? defaultReminderTime
                overdueFollowUpsEnabled = settings.overdueFollowUpsEnabled
            }
            permissionStatus = await NotificationService.permissionStatus()
            householdName = settings?.householdName ?? ""
            darkModeEnabled = settings?.darkMode ?? false
            weekStartsMonday = settings?.weekStartsMonday ?? true
            if settings?.notificationsEnabled == true {
                if permissionStatus == .notDetermined {
                    let granted = (try? await NotificationService.requestPermission()) ?? false
                    permissionStatus = await NotificationService.permissionStatus()
                    if !granted { settings?.notificationsEnabled = false; try await db.updateSettings(householdName: nil, darkMode: nil, notificationsEnabled: false, weekStartsMonday: nil) }
                }
                if permissionStatus == .authorized { await db.refreshNotifications(); notificationError = db.notificationError }
            }
        } catch {
            print("Load error: \(error)")
        }
        loading = false
        refreshing = false
    }

    private func toggleSetting(_ key: String, _ value: Bool) async {
        guard var s = settings else { return }
        switch key {
        case "dark_mode":
            s.darkMode = value
            darkModeEnabled = value
        case "notifications_enabled":
            if value {
                do {
                    let granted = try await NotificationService.requestPermission()
                    guard granted else {
                        notificationError = "Notification permission was denied. Enable Tidyly in iPhone Settings → Notifications."
                        return
                    }
                } catch {
                    notificationError = error.localizedDescription
                    return
                }
            } else {
                await NotificationService.disableAll()
            }
            s.notificationsEnabled = value
        case "week_starts_monday":
            s.weekStartsMonday = value
            weekStartsMonday = value
        default: break
        }
        settings = s
        do {
            try await db.updateSettings(
                householdName: key == "household_name" ? nil : nil,
                darkMode: key == "dark_mode" ? value : nil,
                notificationsEnabled: key == "notifications_enabled" ? value : nil,
                weekStartsMonday: key == "week_starts_monday" ? value : nil
            )
            if key == "notifications_enabled" { permissionStatus = await NotificationService.permissionStatus(); await db.refreshNotifications(); notificationError = db.notificationError }
        } catch {
            if key == "dark_mode" {
                darkModeEnabled.toggle()
                settings?.darkMode = darkModeEnabled
            }
            if key == "week_starts_monday" {
                weekStartsMonday.toggle()
                settings?.weekStartsMonday = weekStartsMonday
            }
            if key == "notifications_enabled" {
                if value { await NotificationService.disableAll() } else { await db.refreshNotifications() }
                settings?.notificationsEnabled = !value
            }
            print("Update error: \(error)")
        }
    }

    private var permissionLabel: String {
        switch permissionStatus { case .authorized: return "Notification permission granted"; case .denied: return "Permission denied in iPhone Settings"; case .notDetermined: return "Permission not requested yet" }
    }

    private func saveReminderSettings() async {
        guard settings != nil else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: defaultReminderTime)
        do {
            try await db.updateReminderSettings(hour: components.hour ?? 9, minute: components.minute ?? 0, overdueFollowUpsEnabled: overdueFollowUpsEnabled)
            settings?.defaultReminderHour = components.hour ?? 9
            settings?.defaultReminderMinute = components.minute ?? 0
            settings?.overdueFollowUpsEnabled = overdueFollowUpsEnabled
            notificationError = db.notificationError
        } catch { notificationError = error.localizedDescription }
    }

    private func saveName() async {
        guard !householdName.isEmpty else { return }
        do {
            try await db.updateSettings(householdName: householdName, darkMode: nil, notificationsEnabled: nil, weekStartsMonday: nil)
            settings?.householdName = householdName
            editingName = false
        } catch {
            print("Save error: \(error)")
        }
    }

    private func exportData() async {
        do {
            async let roomsResult = db.fetchRooms()
            async let tasksResult = db.fetchAllTasks()
            async let activityResult = db.fetchActivityEvents()
            async let settingsResult = db.fetchSettings()
            let (rooms, tasks, activity, exportedSettings) = try await (roomsResult, tasksResult, activityResult, settingsResult)
            let backup = TidylyBackup(
                formatVersion: TidylyBackup.currentVersion,
                exportedAt: Date(),
                rooms: rooms,
                tasks: tasks,
                completions: try db.fetchAllCompletions(),
                activityEvents: activity,
                settings: exportedSettings
            )
            exportDocument = TidylyBackupDocument(backup: backup)
            dataTransferStatus = "Backup ready. Choose iCloud Drive or another Files location."
            showingExporter = true
        } catch {
            dataTransferStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Tidyly-Backup-\(formatter.string(from: Date()))"
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let backup = try TidylyBackupDocument.decoder.decode(TidylyBackup.self, from: data)
            guard backup.formatVersion == TidylyBackup.currentVersion else {
                throw CocoaError(.fileReadUnknown)
            }
            pendingImport = backup
            showingImportConfirmation = true
            dataTransferStatus = "Backup validated. Confirm import to continue."
        } catch {
            pendingImport = nil
            dataTransferStatus = "Import failed: the selected file is not a valid Tidyly backup."
        }
    }

    private func performImport() async {
        guard let pendingImport else { return }
        do {
            try await db.replaceData(with: pendingImport)
            self.pendingImport = nil
            dataTransferStatus = "Import complete: \(pendingImport.rooms.count) rooms and \(pendingImport.tasks.count) tasks restored."
            await loadData()
        } catch {
            dataTransferStatus = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper Views

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ColorAsset.textTertiary.color)
                .textCase(.uppercase)
                .padding(.leading, 4)
            content()
                .padding(AppTheme.spacingLg)
                .background(ColorAsset.surface.color)
                .cornerRadius(AppTheme.cornerLg)
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        }
    }
}

private struct SettingIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 40, height: 40)
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
        }
    }
}

private struct ToggleRow: View {
    let icon: String
    let color: Color
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            SettingIcon(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ColorAsset.text.color)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ColorAsset.primary.color)
        }
        .padding(.vertical, AppTheme.spacingSm)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let label: String
    let desc: String

    var body: some View {
        HStack {
            SettingIcon(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ColorAsset.text.color)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(ColorAsset.textTertiary.color)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ColorAsset.success.color)
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ColorAsset.success.color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ColorAsset.success.color.opacity(0.12))
            .cornerRadius(999)
        }
        .padding(.vertical, AppTheme.spacingSm)
    }
}

private struct ButtonRow: View {
    let icon: String
    let color: Color
    let label: String
    var labelColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                SettingIcon(icon: icon, color: color)
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(labelColor ?? ColorAsset.text.color)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorAsset.textTertiary.color)
            }
            .padding(.vertical, AppTheme.spacingSm)
        }
        .buttonStyle(.plain)
    }
}
