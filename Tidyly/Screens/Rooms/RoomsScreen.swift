import SwiftUI
import UniformTypeIdentifiers

struct RoomsScreen: View {
    @EnvironmentObject var db: DatabaseService
    @State private var rooms: [RoomWithTasks] = []
    @State private var loading = true
    @State private var refreshing = false
    @State private var showRoomEditor = false
    @State private var editingRoom: Room?
    @State private var draggedRoomId: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingMd) {
                    if rooms.isEmpty && !loading {
                        EmptyStateView(icon: "plus", title: "No rooms yet", subtitle: "Add your first room to start organizing cleaning tasks.")
                            .padding(.horizontal, AppTheme.spacingXl)
                    } else {
                        LazyVStack(spacing: AppTheme.spacingMd) {
                            ForEach(rooms) { rwt in
                                NavigationLink {
                                    RoomDetailScreen(room: rwt)
                                } label: {
                                    RoomProgressCard(
                                        room: rwt.room,
                                        completionRate: rwt.completionRate,
                                        dueCount: rwt.dueCount,
                                        overdueCount: rwt.overdueCount,
                                        taskCount: rwt.tasks.count
                                    )
                                }
                                .buttonStyle(.plain)
                                .opacity(draggedRoomId == rwt.id ? 0.55 : 1)
                                .scaleEffect(draggedRoomId == rwt.id ? 1.02 : 1)
                                .onDrag {
                                    draggedRoomId = rwt.id
                                    return NSItemProvider(object: rwt.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: RoomDropDelegate(
                                        targetRoomId: rwt.id,
                                        rooms: $rooms,
                                        draggedRoomId: $draggedRoomId,
                                        onDropCompleted: persistRoomOrder
                                    )
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingXl)
                    }

                    // Add room button
                    Button {
                        editingRoom = nil
                        showRoomEditor = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Add New Room")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(ColorAsset.primary.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerLg)
                                .stroke(ColorAsset.border.color, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppTheme.spacingXl)

                    Spacer().frame(height: 100)
                }
            }
            .navigationTitle("Rooms")
            .background(ColorAsset.background.color.ignoresSafeArea())
            .refreshable { await loadData() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingRoom = nil
                        showRoomEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(ColorAsset.primary.color)
                    }
                }
            }
            .sheet(isPresented: $showRoomEditor, onDismiss: {
                _Concurrency.Task { await loadData() }
            }) {
                RoomEditorSheet(room: editingRoom, onSaved: { _Concurrency.Task { await loadData() } })
                    .presentationDetents([.large])
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .taskScheduleDidChange)) { _ in
            _Concurrency.Task { await loadData() }
        }
    }

    private func loadData() async {
        do {
            rooms = try await db.fetchRoomsWithTasks()
        } catch {
            print("Load error: \(error)")
        }
        loading = false
        refreshing = false
    }

    private func persistRoomOrder(_ orderedRooms: [RoomWithTasks]) {
        let ids = orderedRooms.map(\.id)
        _Concurrency.Task {
            do {
                try await db.updateRoomOrder(ids)
            } catch {
                print("Reorder error: \(error)")
                await loadData()
            }
        }
    }
}

private struct RoomDropDelegate: DropDelegate {
    let targetRoomId: UUID
    @Binding var rooms: [RoomWithTasks]
    @Binding var draggedRoomId: UUID?
    let onDropCompleted: ([RoomWithTasks]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedRoomId,
              draggedRoomId != targetRoomId,
              let sourceIndex = rooms.firstIndex(where: { $0.id == draggedRoomId }),
              let targetIndex = rooms.firstIndex(where: { $0.id == targetRoomId }) else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            rooms.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedRoomId = nil
        onDropCompleted(rooms)
        return true
    }
}

// MARK: - Room Detail

struct RoomDetailScreen: View {
    @EnvironmentObject var db: DatabaseService
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let room: RoomWithTasks
    @State private var tasks: [Task] = []
    @State private var rooms: [Room] = []
    @State private var showTaskEditor = false
    @State private var editingTask: Task?
    @State private var showRoomEditor = false
    @State private var savingTaskIds: Set<UUID> = []
    @State private var undoItem: (task: Task, completionId: UUID)?
    @State private var undoDismissTask: _Concurrency.Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var rescheduleUndoItem: (task: Task, action: TaskRescheduleAction)?
    @State private var rescheduleDismissTask: _Concurrency.Task<Void, Never>?

    private var today: String { DatabaseService.todayISO() }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingLg) {
                // Stats row
                HStack(spacing: AppTheme.spacingMd) {
                    StatBox(value: "\(tasks.count)", label: "Total Tasks")
                    StatBox(value: "\(dueCount)", label: "Due Now")
                    StatBox(value: "\(overdueCount)", label: "Overdue", color: ColorAsset.error.color)
                }
                .padding(.horizontal, AppTheme.spacingXl)

                // Tasks
                if tasks.isEmpty {
                    EmptyStateView(icon: nil, title: "No tasks yet", subtitle: "Add cleaning tasks for this room.")
                        .padding(.horizontal, AppTheme.spacingXl)
                } else {
                    LazyVStack(spacing: AppTheme.spacingMd) {
                        ForEach(tasks) { task in
                            TaskRow(task: task, isSaving: savingTaskIds.contains(task.id), onComplete: {
                                _Concurrency.Task { await completeTask(task) }
                            }, onReschedule: { action in
                                _Concurrency.Task { await reschedule(task, action: action) }
                            })
                            .onTapGesture {
                                editingTask = task
                                showTaskEditor = true
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)
                }

                // Add task
                Button {
                    editingTask = nil
                    showTaskEditor = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Add Task to \(room.room.name)")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(ColorAsset.primary.color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerLg)
                            .stroke(ColorAsset.border.color, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.spacingXl)

                Spacer().frame(height: 40)
            }
        }
        .navigationTitle(room.room.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(ColorAsset.background.color.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showRoomEditor = true
                }
            }
        }
        .sheet(isPresented: $showTaskEditor) {
            TaskEditorSheet(room: room.room, task: editingTask, rooms: rooms, onSaved: { _Concurrency.Task { await loadData() } })
        }
        .sheet(isPresented: $showRoomEditor) {
            RoomEditorSheet(room: room.room, onSaved: { _Concurrency.Task { await loadData() } })
        }
        .safeAreaInset(edge: .bottom) {
            if let rescheduleUndoItem {
                ActionUndoBanner(
                    message: rescheduleUndoItem.action.feedbackMessage(for: rescheduleUndoItem.task),
                    isSaving: savingTaskIds.contains(rescheduleUndoItem.task.id)
                ) {
                    _Concurrency.Task { await undoReschedule(rescheduleUndoItem.task) }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else if let undoItem {
                CompletionUndoBanner(taskTitle: undoItem.task.title, isSaving: savingTaskIds.contains(undoItem.task.id)) {
                    _Concurrency.Task { await undo(undoItem.task, completionId: undoItem.completionId) }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .taskScheduleDidChange)) { _ in
            _Concurrency.Task { await loadData() }
        }
    }

    private var dueCount: Int {
        tasks.filter { DatabaseService.dateOnlyFormatter.string(from: $0.nextDueAt) <= today }.count
    }

    private var overdueCount: Int {
        tasks.filter { DatabaseService.dateOnlyFormatter.string(from: $0.nextDueAt) < today }.count
    }

    private func loadData() async {
        do {
            async let tasksResult = db.fetchAllTasks()
            async let roomsResult = db.fetchRooms()
            let (allTasks, allRooms) = try await (tasksResult, roomsResult)
            tasks = allTasks.filter { $0.roomId == room.room.id }.sorted { $0.nextDueAt < $1.nextDueAt }
            rooms = allRooms
        } catch {
            print("Load error: \(error)")
        }
    }

    private func completeTask(_ task: Task) async {
        guard !savingTaskIds.contains(task.id) else { return }
        savingTaskIds.insert(task.id)
        withAnimation(reduceMotion ? nil : .snappy) { tasks.removeAll { $0.id == task.id } }
        do {
            let completion = try await db.completeTask(task, completedDate: today)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showUndo(for: task, completionId: completion.id)
        } catch {
            withAnimation(reduceMotion ? nil : .snappy) {
                tasks.append(task)
                tasks.sort { $0.nextDueAt < $1.nextDueAt }
            }
            errorMessage = error.localizedDescription
        }
        savingTaskIds.remove(task.id)
    }

    private func undo(_ task: Task, completionId: UUID) async {
        guard !savingTaskIds.contains(task.id) else { return }
        savingTaskIds.insert(task.id)
        do {
            try await db.undoCompletion(id: completionId, taskBeforeCompletion: task)
            withAnimation(reduceMotion ? nil : .snappy) {
                tasks.append(task)
                tasks.sort { $0.nextDueAt < $1.nextDueAt }
            }
            dismissUndo()
        } catch {
            errorMessage = error.localizedDescription
        }
        savingTaskIds.remove(task.id)
    }

    private func showUndo(for task: Task, completionId: UUID) {
        undoDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { undoItem = (task, completionId) }
        UIAccessibility.post(notification: .announcement, argument: "\(task.title) completed. Undo available.")
        undoDismissTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(6))
            guard !_Concurrency.Task.isCancelled else { return }
            await MainActor.run { dismissUndo() }
        }
    }

    private func dismissUndo() {
        undoDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { undoItem = nil }
    }

    private func reschedule(_ task: Task, action: TaskRescheduleAction) async {
        guard !savingTaskIds.contains(task.id) else { return }
        savingTaskIds.insert(task.id)
        do {
            try await db.rescheduleTask(task, action: action)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showRescheduleUndo(for: task, action: action)
        } catch { errorMessage = error.localizedDescription }
        savingTaskIds.remove(task.id)
    }

    private func undoReschedule(_ task: Task) async {
        guard !savingTaskIds.contains(task.id) else { return }
        savingTaskIds.insert(task.id)
        do {
            try await db.restoreTaskSchedule(task)
            dismissRescheduleUndo()
        } catch { errorMessage = error.localizedDescription }
        savingTaskIds.remove(task.id)
    }

    private func showRescheduleUndo(for task: Task, action: TaskRescheduleAction) {
        rescheduleDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { rescheduleUndoItem = (task, action) }
        UIAccessibility.post(notification: .announcement, argument: "\(action.feedbackMessage(for: task)). Undo available.")
        rescheduleDismissTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(6))
            guard !_Concurrency.Task.isCancelled else { return }
            await MainActor.run { dismissRescheduleUndo() }
        }
    }

    private func dismissRescheduleUndo() {
        rescheduleDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { rescheduleUndoItem = nil }
    }
}

private struct StatBox: View {
    let value: String
    let label: String
    var color: Color = ColorAsset.text.color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ColorAsset.textTertiary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.spacingMd)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

private struct TaskRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let task: Task
    var isSaving: Bool = false
    var onComplete: () -> Void
    var onReschedule: (TaskRescheduleAction) -> Void

    private var dueDateStr: String {
        DatabaseService.dateOnlyFormatter.string(from: task.nextDueAt)
    }

    private var isOverdue: Bool {
        DatabaseService.daysUntil(dueDateStr) < 0
    }

    private var isDueToday: Bool {
        DatabaseService.daysUntil(dueDateStr) == 0
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
                    HStack(alignment: .top, spacing: AppTheme.spacingMd) {
                        completionButton
                        taskTitle
                        Spacer(minLength: AppTheme.spacingSm)
                        TaskRescheduleMenu(task: task, isSaving: isSaving, onReschedule: onReschedule)
                    }
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        metadata
                        dueBadge
                    }
                }
            } else {
                HStack(spacing: AppTheme.spacingMd) {
                    completionButton
                    VStack(alignment: .leading, spacing: AppTheme.spacingXs) {
                        taskTitle
                        metadata
                    }
                    Spacer(minLength: AppTheme.spacingSm)
                    dueBadge
                    TaskRescheduleMenu(task: task, isSaving: isSaving, onReschedule: onReschedule)
                }
            }
        }
        .padding(AppTheme.spacingLg)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        .accessibilityElement(children: .contain)
    }

    private var completionButton: some View {
        Button(action: onComplete) {
            ZStack {
                Circle().strokeBorder(ColorAsset.borderDark.color, lineWidth: 2)
                if isSaving { ProgressView().controlSize(.small) }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Complete \(task.title)")
        .accessibilityHint("Marks this task complete")
    }

    private var taskTitle: some View {
        Text(task.title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(ColorAsset.text.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.spacingSm) { metadataItems }
            VStack(alignment: .leading, spacing: AppTheme.spacingSm) { metadataItems }
        }
    }

    @ViewBuilder
    private var metadataItems: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(task.priority.color.color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(task.priority.label)
                .foregroundColor(task.priority.color.color)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(task.priority.color.color.opacity(0.12))
        .cornerRadius(8)

        HStack(spacing: 3) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
            Text("\(task.estimatedMinutes)m")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption.weight(.medium))
        .foregroundColor(ColorAsset.textTertiary.color)

        Text("Every \(task.frequencyDays)d")
            .font(.caption.weight(.medium))
            .foregroundColor(ColorAsset.textTertiary.color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var dueBadge: some View {
        HStack(spacing: 4) {
            if isOverdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .accessibilityHidden(true)
            }
            Text(DatabaseService.formatRelativeDate(dueDateStr))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
            .font(.caption.weight(.semibold))
            .foregroundColor(isOverdue ? ColorAsset.error.color : isDueToday ? ColorAsset.primary.color : ColorAsset.textSecondary.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isOverdue ? ColorAsset.error.color : isDueToday ? ColorAsset.primary.color : ColorAsset.surfaceAlt.color).opacity(0.12)
            )
            .cornerRadius(10)
    }
}
