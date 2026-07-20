import SwiftUI

struct RoomEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var db: DatabaseService

    let room: Room?
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var icon: String = AppTheme.roomIcons[0]
    @State private var color: String = AppTheme.roomColors[0]
    @State private var saving = false
    @State private var showDeleteConfirm = false
    @State private var saveError: String?
    @State private var selectedSuggestionIds: Set<String> = []
    @State private var remindersEnabled = true

    private let pickerColumns = [
        GridItem(.adaptive(minimum: 44, maximum: 52), spacing: AppTheme.spacingSm)
    ]

    private var suggestions: [TaskSuggestion] {
        TaskSuggestionCatalog.suggestions(for: name)
    }

    private var selectedSuggestions: [TaskSuggestion] {
        suggestions.filter { selectedSuggestionIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
                    // Name
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        Text("Room Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ColorAsset.textSecondary.color)
                        TextField("e.g. Garage", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, AppTheme.spacingMd)

                    Toggle("Allow reminders for this room", isOn: $remindersEnabled)
                        .font(.body.weight(.semibold))
                        .padding(AppTheme.spacingLg)
                        .background(ColorAsset.surfaceAlt.color)
                        .cornerRadius(AppTheme.cornerMd)

                    if room == nil {
                        starterTasksSection
                    }

                    // Icon
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        Text("Icon")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ColorAsset.textSecondary.color)
                        LazyVGrid(columns: pickerColumns, spacing: AppTheme.spacingSm) {
                            ForEach(AppTheme.roomIcons, id: \.self) { ic in
                                Text(ic)
                                    .font(.system(size: 24))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(
                                        icon == ic ? ColorAsset.primaryLight.color : ColorAsset.surfaceAlt.color
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.cornerMd)
                                            .stroke(icon == ic ? ColorAsset.primary.color : Color.clear, lineWidth: 2)
                                    )
                                    .cornerRadius(AppTheme.cornerMd)
                                    .onTapGesture { icon = ic }
                            }
                        }
                    }
                    .padding(.top, AppTheme.spacingMd)

                    // Color
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        Text("Color")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ColorAsset.textSecondary.color)
                        LazyVGrid(columns: pickerColumns, spacing: AppTheme.spacingMd) {
                            ForEach(AppTheme.roomColors, id: \.self) { c in
                                Circle()
                                    .fill(Color(hex: c))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(color == c ? ColorAsset.text.color : Color.clear, lineWidth: 3)
                                    )
                                    .onTapGesture { color = c }
                            }
                        }
                    }
                    .padding(.top, AppTheme.spacingMd)

                    // Actions
                    HStack(spacing: AppTheme.spacingMd) {
                        if room != nil {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 18))
                                    .frame(width: 52, height: 52)
                                    .background(ColorAsset.error.color.opacity(0.08))
                                    .cornerRadius(AppTheme.cornerMd)
                            }
                        }

                        Button {
                            _Concurrency.Task { await save() }
                        } label: {
                            Text(saveButtonTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(name.isEmpty ? ColorAsset.primary.color.opacity(0.5) : ColorAsset.primary.color)
                                .cornerRadius(AppTheme.cornerMd)
                        }
                        .disabled(name.isEmpty || saving)
                    }
                    .padding(.top, AppTheme.spacingXxl)
                }
                .padding(.horizontal, AppTheme.spacingXl)
                .padding(.bottom, 40)
            }
            .navigationTitle(room != nil ? "Edit Room" : "New Room")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete Room", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    _Concurrency.Task {
                        if let room {
                            try? await db.deleteRoom(id: room.id)
                            onSaved()
                            dismiss()
                        }
                    }
                }
            } message: {
                if let room {
                    Text("Delete \"\(room.name)\" and all its tasks? This cannot be undone.")
                }
            }
            .alert("Couldn’t Save Room", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
        .onAppear {
            if let room {
                name = room.name
                icon = room.icon
                color = room.color
                remindersEnabled = room.remindersEnabled
            } else {
                selectedSuggestionIds = Set(suggestions.map(\.id))
            }
        }
        .onChange(of: suggestions.map(\.id)) { oldIds, newIds in
            guard room == nil, oldIds != newIds else { return }
            selectedSuggestionIds = Set(newIds)
        }
    }

    private var saveButtonTitle: String {
        if saving { return "Saving..." }
        if room != nil { return "Save Changes" }
        let count = selectedSuggestions.count
        return count == 0 ? "Add Room" : "Add Room & \(count) Task\(count == 1 ? "" : "s")"
    }

    private var starterTasksSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Starter Tasks")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(ColorAsset.text.color)
                    Text("Choose what to add with this room.")
                        .font(.system(size: 12))
                        .foregroundColor(ColorAsset.textTertiary.color)
                }
                Spacer()
                Button("Select All") { selectedSuggestionIds = Set(suggestions.map(\.id)) }
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(selectedSuggestionIds.count == suggestions.count)
                Button("Clear") { selectedSuggestionIds.removeAll() }
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(selectedSuggestionIds.isEmpty)
            }

            VStack(spacing: AppTheme.spacingSm) {
                ForEach(suggestions) { suggestion in
                    let isSelected = selectedSuggestionIds.contains(suggestion.id)
                    Button {
                        if isSelected {
                            selectedSuggestionIds.remove(suggestion.id)
                        } else {
                            selectedSuggestionIds.insert(suggestion.id)
                        }
                    } label: {
                        HStack(spacing: AppTheme.spacingMd) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(isSelected ? ColorAsset.primary.color : ColorAsset.borderDark.color)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(ColorAsset.text.color)
                                HStack(spacing: AppTheme.spacingMd) {
                                    Label(frequencyLabel(suggestion.frequencyDays), systemImage: "repeat")
                                    Label("\(suggestion.estimatedMinutes) min", systemImage: "clock")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ColorAsset.textTertiary.color)
                            }
                            Spacer()
                        }
                        .padding(AppTheme.spacingMd)
                        .background(isSelected ? ColorAsset.primaryLight.color.opacity(0.55) : ColorAsset.surfaceAlt.color)
                        .cornerRadius(AppTheme.cornerMd)
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerMd).stroke(isSelected ? ColorAsset.primary.color.opacity(0.4) : ColorAsset.border.color))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(suggestion.title), \(frequencyLabel(suggestion.frequencyDays)), \(suggestion.estimatedMinutes) minutes")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
        }
        .padding(.top, AppTheme.spacingMd)
    }

    private func frequencyLabel(_ days: Int) -> String {
        switch days {
        case 1: return "Daily"
        case 7: return "Weekly"
        case 14: return "Every 2 weeks"
        case 30: return "Monthly"
        default: return "Every \(days) days"
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            if let room {
                try await db.updateRoom(id: room.id, name: trimmedName, icon: icon, color: color)
                try await db.updateRoomReminders(id: room.id, enabled: remindersEnabled)
            } else {
                let newRoom = try await db.createRoom(
                    name: trimmedName,
                    icon: icon,
                    color: color,
                    starterTasks: selectedSuggestions
                )
                try await db.updateRoomReminders(id: newRoom.id, enabled: remindersEnabled)
            }
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
