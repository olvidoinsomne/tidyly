import SwiftUI

struct TaskEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var db: DatabaseService

    let room: Room
    let task: Task?
    let rooms: [Room]
    var onSaved: () -> Void

    @State private var title: String = ""
    @State private var frequency: Int = 7
    @State private var priority: Priority = .medium
    @State private var minutes: Int = 10
    @State private var selectedRoomId: UUID
    @State private var saving = false
    @State private var showDeleteConfirm = false

    private var selectedRoom: Room {
        rooms.first(where: { $0.id == selectedRoomId }) ?? room
    }

    private var suggestions: [TaskSuggestion] {
        TaskSuggestionCatalog.suggestions(for: selectedRoom.name)
    }

    init(room: Room, task: Task?, rooms: [Room], onSaved: @escaping () -> Void) {
        self.room = room
        self.task = task
        self.rooms = rooms
        self.onSaved = onSaved
        _selectedRoomId = State(initialValue: task?.roomId ?? room.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
                    // Title
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        Text("Task Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ColorAsset.textSecondary.color)
                        TextField("e.g. Vacuum the carpet", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, AppTheme.spacingMd)

                    if task == nil {
                        VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Suggested for \(selectedRoom.name)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(ColorAsset.textSecondary.color)
                                    Text("Tap a task to use its recommended schedule.")
                                        .font(.system(size: 11))
                                        .foregroundColor(ColorAsset.textTertiary.color)
                                }
                                Spacer()
                                Button("Add All") {
                                    _Concurrency.Task { await addAllSuggestions() }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .disabled(saving)
                            }

                            FlowLayout(spacing: AppTheme.spacingSm) {
                                ForEach(suggestions) { suggestion in
                                    Button {
                                        apply(suggestion)
                                    } label: {
                                        Text(suggestion.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(ColorAsset.primary.color)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
                                            .background(ColorAsset.primaryLight.color)
                                            .cornerRadius(999)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, AppTheme.spacingMd)
                    }

                    // Room
                    if !rooms.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                            Text("Room")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ColorAsset.textSecondary.color)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppTheme.spacingSm) {
                                    ForEach(rooms) { r in
                                        HStack(spacing: 6) {
                                            Text(r.icon)
                                                .font(.system(size: 16))
                                            Text(r.name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(selectedRoomId == r.id ? .white : ColorAsset.textSecondary.color)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedRoomId == r.id ? Color(hex: r.color) : ColorAsset.surfaceAlt.color
                                        )
                                        .cornerRadius(999)
                                        .onTapGesture { selectedRoomId = r.id }
                                    }
                                }
                            }
                        }
                        .padding(.top, AppTheme.spacingMd)
                    }

                    // Frequency
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        Text("Frequency")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ColorAsset.textSecondary.color)
                        FlowLayout(spacing: AppTheme.spacingSm) {
                            ForEach(AppTheme.frequencies, id: \.value) { freq in
                                Text(freq.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(frequency == freq.value ? .white : ColorAsset.textSecondary.color)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(frequency == freq.value ? ColorAsset.primary.color : ColorAsset.surfaceAlt.color)
                                    .cornerRadius(999)
                                    .onTapGesture { frequency = freq.value }
                            }
                        }
                    }
                    .padding(.top, AppTheme.spacingMd)

                    // Priority
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        Text("Priority")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ColorAsset.textSecondary.color)
                        HStack(spacing: AppTheme.spacingSm) {
                            ForEach(Priority.allCases, id: \.self) { p in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(p.color.color)
                                        .frame(width: 8, height: 8)
                                    Text(p.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(priority == p ? p.color.color : ColorAsset.textSecondary.color)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    priority == p ? p.color.color.opacity(0.12) : ColorAsset.surfaceAlt.color
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 999)
                                        .stroke(priority == p ? p.color.color : Color.clear, lineWidth: 2)
                                )
                                .cornerRadius(999)
                                .onTapGesture { priority = p }
                            }
                        }
                    }
                    .padding(.top, AppTheme.spacingMd)

                    // Minutes
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        Text("Estimated Time")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ColorAsset.textSecondary.color)
                        HStack {
                            Button {
                                minutes = max(1, minutes - 5)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 44, height: 44)
                                    .background(ColorAsset.surfaceAlt.color)
                                    .cornerRadius(22)
                                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(ColorAsset.border.color, lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Text("\(minutes) min")
                                .font(.system(size: 20, weight: .bold))
                                .frame(minWidth: 80)

                            Button {
                                minutes = min(240, minutes + 5)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 44, height: 44)
                                    .background(ColorAsset.surfaceAlt.color)
                                    .cornerRadius(22)
                                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(ColorAsset.border.color, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, AppTheme.spacingMd)

                    // Actions
                    HStack(spacing: AppTheme.spacingMd) {
                        if task != nil {
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
                            Text(saving ? "Saving..." : (task != nil ? "Save Changes" : "Add Task"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(title.isEmpty ? ColorAsset.primary.color.opacity(0.5) : ColorAsset.primary.color)
                                .cornerRadius(AppTheme.cornerMd)
                        }
                        .disabled(title.isEmpty || saving)
                    }
                    .padding(.top, AppTheme.spacingXxl)
                }
                .padding(.horizontal, AppTheme.spacingXl)
                .padding(.bottom, 40)
            }
            .navigationTitle(task != nil ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete Task", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    _Concurrency.Task {
                        if let task {
                            try? await db.deleteTask(id: task.id)
                            onSaved()
                            dismiss()
                        }
                    }
                }
            } message: {
                if let task {
                    Text("Delete \"\(task.title)\"?")
                }
            }
        }
        .onAppear {
            if let task {
                title = task.title
                frequency = task.frequencyDays
                priority = task.priority
                minutes = task.estimatedMinutes
                selectedRoomId = task.roomId
            }
        }
    }

    private func save() async {
        guard !title.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            if let task {
                try await db.updateTask(
                    id: task.id,
                    title: title,
                    frequencyDays: frequency,
                    priority: priority,
                    estimatedMinutes: minutes,
                    roomId: selectedRoomId
                )
            } else {
                _ = try await db.createTask(
                    roomId: selectedRoomId,
                    title: title,
                    frequencyDays: frequency,
                    priority: priority,
                    estimatedMinutes: minutes
                )
            }
            onSaved()
            dismiss()
        } catch {
            print("Save error: \(error)")
        }
    }

    private func apply(_ suggestion: TaskSuggestion) {
        title = suggestion.title
        frequency = suggestion.frequencyDays
        priority = suggestion.priority
        minutes = suggestion.estimatedMinutes
    }

    private func addAllSuggestions() async {
        saving = true
        defer { saving = false }
        do {
            let existingTitles = Set(
                try await db.fetchAllTasks()
                    .filter { $0.roomId == selectedRoomId }
                    .map { $0.title.lowercased() }
            )
            for suggestion in suggestions where !existingTitles.contains(suggestion.title.lowercased()) {
                _ = try await db.createTask(
                    roomId: selectedRoomId,
                    title: suggestion.title,
                    frequencyDays: suggestion.frequencyDays,
                    priority: suggestion.priority,
                    estimatedMinutes: suggestion.estimatedMinutes
                )
            }
            onSaved()
            dismiss()
        } catch {
            print("Add suggestions error: \(error)")
        }
    }
}

// Simple flow layout for wrapping chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
