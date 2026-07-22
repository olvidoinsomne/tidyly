import SwiftUI

struct TodayScreen: View {
    @EnvironmentObject var db: DatabaseService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tasks: [TaskWithRoom] = []
    @State private var rooms: [Room] = []
    @State private var completedIds: Set<UUID> = []
    @State private var completionIds: [UUID: UUID] = [:]
    @State private var loading = true
    @State private var refreshing = false
    @State private var showAddTask = false
    @State private var savingTaskIds: Set<UUID> = []
    @State private var undoItem: (task: TaskWithRoom, completionId: UUID)?
    @State private var undoDismissTask: _Concurrency.Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var rescheduleUndoItem: (task: TaskWithRoom, action: TaskRescheduleAction)?
    @State private var rescheduleDismissTask: _Concurrency.Task<Void, Never>?

    private var today: String { DatabaseService.todayISO() }

    private var pendingTasks: [TaskWithRoom] {
        tasks.filter { !completedIds.contains($0.task.id) }
    }

    private var completedTasks: [TaskWithRoom] {
        tasks.filter { completedIds.contains($0.task.id) }
    }

    private var completionRate: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTasks.count) / Double(tasks.count)
    }

    private var totalMinutes: Int {
        pendingTasks.reduce(0) { $0 + $1.task.estimatedMinutes }
    }

    private var overdueCount: Int {
        pendingTasks.filter { DatabaseService.daysUntil(DatabaseService.dateOnlyFormatter.string(from: $0.task.nextDueAt)) < 0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingLg) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DatabaseService.formatFullDate(today))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(ColorAsset.textTertiary.color)
                                .textCase(.uppercase)
                            Text("Let's get cleaning!")
                                .font(.system(size: 30, weight: .heavy))
                                .foregroundColor(ColorAsset.text.color)
                        }
                        Spacer()
                        ProgressRing(progress: completionRate, size: 64, strokeWidth: 7) {
                            Text("\(Int(completionRate * 100))%")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ColorAsset.primary.color)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    // Summary cards
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: AppTheme.spacingMd) {
                                summaryCards
                            }
                        } else {
                            HStack(spacing: AppTheme.spacingMd) {
                                summaryCards
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    // Pending
                    if !pendingTasks.isEmpty {
                        SectionHeader(title: "To Do", count: "\(pendingTasks.count) tasks")
                            .padding(.horizontal, AppTheme.spacingXl)

                        LazyVStack(spacing: AppTheme.spacingMd) {
                            ForEach(pendingTasks) { tw in
                                TaskCardView(taskWithRoom: tw, isSaving: savingTaskIds.contains(tw.task.id), onComplete: {
                                    _Concurrency.Task { await complete(tw) }
                                }, onReschedule: { action in
                                    _Concurrency.Task { await reschedule(tw, action: action) }
                                })
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingXl)
                    }

                    // All done
                    if pendingTasks.isEmpty && !completedTasks.isEmpty {
                        VStack(spacing: AppTheme.spacingSm) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundColor(ColorAsset.success.color)
                            Text("All tasks done!")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(ColorAsset.text.color)
                            Text("Great job keeping your home clean.")
                                .font(.system(size: 13))
                                .foregroundColor(ColorAsset.textTertiary.color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingXxl)
                        .background(ColorAsset.surface.color)
                        .cornerRadius(AppTheme.cornerXl)
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerXl).stroke(ColorAsset.border.color, lineWidth: 1))
                        .padding(.horizontal, AppTheme.spacingXl)
                    }

                    // Completed
                    if !completedTasks.isEmpty {
                        SectionHeader(title: "Completed", count: "\(completedTasks.count) done")
                            .padding(.horizontal, AppTheme.spacingXl)

                        LazyVStack(spacing: AppTheme.spacingMd) {
                            ForEach(completedTasks) { tw in
                                TaskCardView(taskWithRoom: tw, isCompleted: true, isSaving: savingTaskIds.contains(tw.task.id), onUndo: {
                                    _Concurrency.Task { await undo(tw) }
                                })
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingXl)
                    }

                    // Empty
                    if tasks.isEmpty && !loading {
                        EmptyStateView(icon: "sparkles", title: "All done for today!", subtitle: "No tasks due. Enjoy your clean home.")
                    }

                    Spacer().frame(height: 100)
                }
            }
            .background(ColorAsset.background.color.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SearchScreen()
                            .environmentObject(db)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search tasks")
                }
            }
            .refreshable { await loadData() }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showAddTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(ColorAsset.primary.color)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, AppTheme.spacingXl)
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .bottom) {
                if let rescheduleUndoItem {
                    ActionUndoBanner(
                        message: rescheduleUndoItem.action.feedbackMessage(for: rescheduleUndoItem.task.task),
                        isSaving: savingTaskIds.contains(rescheduleUndoItem.task.task.id)
                    ) {
                        _Concurrency.Task { await undoReschedule(rescheduleUndoItem.task) }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                } else if let undoItem {
                    CompletionUndoBanner(taskTitle: undoItem.task.task.title, isSaving: savingTaskIds.contains(undoItem.task.task.id)) {
                        _Concurrency.Task { await undo(undoItem.task) }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showAddTask) {
                if let firstRoom = rooms.first {
                    TaskEditorSheet(room: firstRoom, task: nil, rooms: rooms, onSaved: {
                        _Concurrency.Task { await loadData() }
                    })
                } else {
                    NavigationStack {
                        EmptyStateView(
                            icon: "square.grid.2x2",
                            title: "Add a Room First",
                            subtitle: "Tasks need a room. Add one from the Rooms tab, then return here."
                        )
                        .padding(AppTheme.spacingXl)
                        .navigationTitle("New Task")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showAddTask = false }
                            }
                        }
                    }
                }
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .taskScheduleDidChange)) { _ in
            _Concurrency.Task { await loadData() }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    @ViewBuilder
    private var summaryCards: some View {
        SummaryCard(icon: "clock", value: "\(totalMinutes)m", label: "Remaining", color: ColorAsset.primary.color)
        SummaryCard(icon: "flame.fill", value: "\(overdueCount)", label: "Overdue", color: ColorAsset.warning.color)
        SummaryCard(icon: "arrow.up.right", value: "\(completedTasks.count)", label: "Done", color: ColorAsset.success.color)
    }

    private func loadData() async {
        do {
            async let tasksResult = db.fetchTasksForDate(today)
            async let roomsResult = db.fetchRooms()
            async let completionsResult = db.fetchCompletionsInRange(startDate: today, endDate: today)
            let (todayTasks, allRooms, todayCompletions) = try await (tasksResult, roomsResult, completionsResult)
            tasks = todayTasks
            rooms = allRooms

            completedIds = Set(todayCompletions.map(\.taskId))
            completionIds = Dictionary(
                todayCompletions.map { ($0.taskId, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            print("Load error: \(error)")
        }
        loading = false
        refreshing = false
    }

    private func complete(_ tw: TaskWithRoom) async {
        guard !savingTaskIds.contains(tw.task.id) else { return }
        savingTaskIds.insert(tw.task.id)
        _ = withAnimation(reduceMotion ? nil : .snappy) { completedIds.insert(tw.task.id) }
        do {
            let completion = try await db.completeTask(tw.task, completedDate: today)
            completionIds[tw.task.id] = completion.id
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showUndo(for: tw, completionId: completion.id)
        } catch {
            _ = withAnimation(reduceMotion ? nil : .snappy) { completedIds.remove(tw.task.id) }
            errorMessage = error.localizedDescription
        }
        savingTaskIds.remove(tw.task.id)
    }

    private func undo(_ tw: TaskWithRoom) async {
        guard let compId = completionIds[tw.task.id] else { return }
        guard !savingTaskIds.contains(tw.task.id) else { return }
        savingTaskIds.insert(tw.task.id)
        _ = withAnimation(reduceMotion ? nil : .snappy) { completedIds.remove(tw.task.id) }
        do {
            try await db.undoCompletion(id: compId, taskBeforeCompletion: tw.task)
            completionIds.removeValue(forKey: tw.task.id)
            dismissUndo()
        } catch {
            _ = withAnimation(reduceMotion ? nil : .snappy) { completedIds.insert(tw.task.id) }
            errorMessage = error.localizedDescription
        }
        savingTaskIds.remove(tw.task.id)
    }

    private func showUndo(for task: TaskWithRoom, completionId: UUID) {
        undoDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { undoItem = (task, completionId) }
        UIAccessibility.post(notification: .announcement, argument: "\(task.task.title) completed. Undo available.")
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

    private func reschedule(_ task: TaskWithRoom, action: TaskRescheduleAction) async {
        guard !savingTaskIds.contains(task.task.id) else { return }
        savingTaskIds.insert(task.task.id)
        do {
            try await db.rescheduleTask(task.task, action: action)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showRescheduleUndo(for: task, action: action)
        } catch {
            errorMessage = error.localizedDescription
        }
        savingTaskIds.remove(task.task.id)
    }

    private func undoReschedule(_ task: TaskWithRoom) async {
        guard !savingTaskIds.contains(task.task.id) else { return }
        savingTaskIds.insert(task.task.id)
        do {
            try await db.restoreTaskSchedule(task.task)
            dismissRescheduleUndo()
        } catch {
            errorMessage = error.localizedDescription
        }
        savingTaskIds.remove(task.task.id)
    }

    private func showRescheduleUndo(for task: TaskWithRoom, action: TaskRescheduleAction) {
        rescheduleDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { rescheduleUndoItem = (task, action) }
        UIAccessibility.post(notification: .announcement, argument: "\(action.feedbackMessage(for: task.task)). Undo available.")
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

private struct SectionHeader: View {
    let title: String
    let count: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(ColorAsset.text.color)
            Spacer()
            Text(count)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ColorAsset.textTertiary.color)
        }
    }
}

private struct SummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.spacingSm) {
                iconView
                summaryText
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                iconView
                summaryText
            }
        }
        .padding(AppTheme.spacingMd)
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 128 : 76, alignment: .leading)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
        }
        .accessibilityHidden(true)
    }

    private var summaryText: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline.bold())
                .foregroundColor(ColorAsset.text.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(ColorAsset.textTertiary.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
