import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject var db: DatabaseService
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("weekStartsMonday") private var weekStartsMonday = true
    @State private var settings: Settings?
    @State private var loading = true
    @State private var refreshing = false
    @State private var editingName = false
    @State private var householdName = ""
    @State private var showClearConfirm = false
    @State private var notificationError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingXl) {
                    // Household
                    SettingsSection(title: "Household") {
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
                    }

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

                    // Data
                    SettingsSection(title: "Data") {
                        VStack(spacing: 0) {
                            ButtonRow(icon: "square.and.arrow.down", color: ColorAsset.secondary.color, label: "Export Data") {
                                _Concurrency.Task { await exportData() }
                            }
                            Divider().padding(.leading, 56)
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
                                Text("1.0.0")
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
        }
        .task { await loadData() }
    }

    private func loadData() async {
        do {
            settings = try await db.fetchSettings()
            householdName = settings?.householdName ?? ""
            darkModeEnabled = settings?.darkMode ?? false
            weekStartsMonday = settings?.weekStartsMonday ?? true
            if settings?.notificationsEnabled == true {
                let granted = (try? await NotificationService.setEnabled(true)) ?? false
                if !granted {
                    settings?.notificationsEnabled = false
                    try? await db.updateSettings(
                        householdName: nil,
                        darkMode: nil,
                        notificationsEnabled: false,
                        weekStartsMonday: nil
                    )
                }
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
                    let granted = try await NotificationService.setEnabled(true)
                    guard granted else {
                        notificationError = "Notification permission was denied. Enable Tidyly in iPhone Settings → Notifications."
                        return
                    }
                } catch {
                    notificationError = error.localizedDescription
                    return
                }
            } else {
                try? await NotificationService.setEnabled(false)
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
                try? await NotificationService.setEnabled(!value)
                settings?.notificationsEnabled = !value
            }
            print("Update error: \(error)")
        }
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
            async let completionsResult = db.fetchCompletionsInRange(startDate: DatabaseService.addDays(DatabaseService.todayISO(), days: -365), endDate: DatabaseService.todayISO())
            let (rooms, tasks, completions) = try await (roomsResult, tasksResult, completionsResult)
            let data: [String: Any] = [
                "rooms": rooms.map { ["id": $0.id.uuidString, "name": $0.name, "icon": $0.icon, "color": $0.color] },
                "tasks": tasks.map { ["id": $0.id.uuidString, "title": $0.title, "frequency_days": $0.frequencyDays] },
                "completions": completions.map { ["id": $0.id.uuidString, "task_id": $0.taskId.uuidString] },
                "exportDate": ISO8601DateFormatter().string(from: Date())
            ]
            if let json = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
               let jsonStr = String(data: json, encoding: .utf8) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("tidyly-export.json")
                try jsonStr.write(to: url, atomically: true, encoding: .utf8)
                print("Exported to \(url.path)")
            }
        } catch {
            print("Export error: \(error)")
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
