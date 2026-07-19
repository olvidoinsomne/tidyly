import SwiftUI

struct ScheduleScreen: View {
    @EnvironmentObject var db: DatabaseService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("weekStartsMonday") private var weekStartsMonday = true
    @State private var weekStart: String = DatabaseService.getWeekStart()
    @State private var tasks: [TaskWithRoom] = []
    @State private var selectedDate: String = DatabaseService.todayISO()
    @State private var completedIds: Set<UUID> = []
    @State private var loading = true
    @State private var refreshing = false
    @State private var completionIds: [UUID: UUID] = [:]
    @State private var savingTaskIds: Set<UUID> = []
    @State private var undoItem: (task: TaskWithRoom, completionId: UUID)?
    @State private var undoDismissTask: _Concurrency.Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var rescheduleUndoItem: (task: TaskWithRoom, action: TaskRescheduleAction)?
    @State private var rescheduleDismissTask: _Concurrency.Task<Void, Never>?

    private var weekDates: [String] { DatabaseService.getWeekDates(weekStart) }
    private var today: String { DatabaseService.todayISO() }

    private var dayLabels: [String] {
        weekStartsMonday ? ["M", "T", "W", "T", "F", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"]
    }
    private let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    private var monthLabel: String {
        let start = DatabaseService.dateOnlyFormatter.date(from: weekStart) ?? Date()
        let end = DatabaseService.dateOnlyFormatter.date(from: DatabaseService.addDays(weekStart, days: 6)) ?? Date()
        let startCal = Calendar.current.dateComponents([.month, .year], from: start)
        let endCal = Calendar.current.dateComponents([.month, .year], from: end)
        if startCal.month == endCal.month {
            return "\(monthNames[(startCal.month ?? 1) - 1]) \(startCal.year ?? 2026)"
        }
        return "\(monthNames[(startCal.month ?? 1) - 1]) - \(monthNames[(endCal.month ?? 1) - 1]) \(endCal.year ?? 2026)"
    }

    private func tasksForDate(_ dateStr: String) -> [TaskWithRoom] {
        tasks.filter { DatabaseService.dateOnlyFormatter.string(from: $0.task.nextDueAt) == dateStr }
    }

    private var pendingSelected: [TaskWithRoom] {
        tasksForDate(selectedDate).filter { !completedIds.contains($0.task.id) }
    }

    private var completedSelected: [TaskWithRoom] {
        tasksForDate(selectedDate).filter { completedIds.contains($0.task.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingMd) {
                    // Selected date label
                    Text(DatabaseService.formatFullDate(selectedDate))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ColorAsset.textSecondary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if pendingSelected.isEmpty && completedSelected.isEmpty {
                        EmptyStateView(icon: "checkmark.circle", title: "No tasks due", subtitle: "Nothing scheduled for this day.")
                    }

                    // Pending tasks
                    LazyVStack(spacing: AppTheme.spacingMd) {
                        ForEach(pendingSelected) { tw in
                            TaskCardView(taskWithRoom: tw, isSaving: savingTaskIds.contains(tw.task.id), onComplete: {
                                _Concurrency.Task { await complete(tw) }
                            }, onReschedule: { action in
                                _Concurrency.Task { await reschedule(tw, action: action) }
                            })
                        }
                    }

                    // Completed tasks
                    if !completedSelected.isEmpty {
                        LazyVStack(spacing: AppTheme.spacingMd) {
                            ForEach(completedSelected) { tw in
                                TaskCardView(taskWithRoom: tw, isCompleted: true, isSaving: savingTaskIds.contains(tw.task.id), onUndo: {
                                    _Concurrency.Task { await undo(tw) }
                                })
                            }
                        }
                    }

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, AppTheme.spacingXl)
            }
            .navigationTitle("Schedule")
            .background(ColorAsset.background.color.ignoresSafeArea())
            .refreshable { await loadData() }
            .safeAreaInset(edge: .top) {
                // Week calendar
                VStack(spacing: AppTheme.spacingSm) {
                    HStack {
                        Text("Schedule")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundColor(ColorAsset.text.color)
                        Spacer()
                        Button {
                            weekStart = DatabaseService.getWeekStart(weekStartsMonday: weekStartsMonday)
                            selectedDate = today
                        } label: {
                            Text("Today")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ColorAsset.primary.color)
                                .padding(.horizontal, AppTheme.spacingMd)
                                .padding(.vertical, AppTheme.spacingSm)
                                .background(ColorAsset.primaryLight.color)
                                .cornerRadius(999)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)
                    .padding(.top, AppTheme.spacingXl)

                    HStack {
                        Button { goPrevWeek() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(ColorAsset.text.color)
                                .frame(width: 40, height: 40)
                                .background(ColorAsset.surfaceAlt.color)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text(monthLabel)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(ColorAsset.text.color)

                        Button { goNextWeek() } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(ColorAsset.text.color)
                                .frame(width: 40, height: 40)
                                .background(ColorAsset.surfaceAlt.color)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Day cells
                    HStack(spacing: 4) {
                        ForEach(Array(weekDates.enumerated()), id: \.offset) { idx, date in
                            let isToday = date == today
                            let isSelected = date == selectedDate
                            let taskCount = tasksForDate(date).count
                            let isPast = date < today
                            let dayNum = Calendar.current.component(.day, from: DatabaseService.dateOnlyFormatter.date(from: date) ?? Date())

                            VStack(spacing: 4) {
                                Text(dayLabels[idx])
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isSelected ? .white.opacity(0.8) : ColorAsset.textTertiary.color)

                                Text("\(dayNum)")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(isSelected ? .white : isToday ? ColorAsset.primary.color : ColorAsset.text.color)

                                // Dots
                                HStack(spacing: 3) {
                                    if taskCount > 0 {
                                        Circle()
                                            .fill(isSelected ? Color.white : isPast ? ColorAsset.textTertiary.color : ColorAsset.primary.color)
                                            .frame(width: 6, height: 6)
                                    }
                                    if taskCount > 3 {
                                        Circle()
                                            .fill(isSelected ? Color.white : isPast ? ColorAsset.textTertiary.color : ColorAsset.primary.color)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .frame(height: 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacingMd)
                            .background(isSelected ? ColorAsset.primary.color : Color.clear)
                            .cornerRadius(AppTheme.cornerLg)
                            .onTapGesture { selectedDate = date }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingMd)
                }
                .padding(.bottom, AppTheme.spacingMd)
                .background(ColorAsset.background.color)
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
        }
        .task {
            weekStart = DatabaseService.getWeekStart(weekStartsMonday: weekStartsMonday)
            await loadData()
        }
        .onChange(of: weekStartsMonday) { _, newValue in
            weekStart = DatabaseService.getWeekStart(weekStartsMonday: newValue)
            selectedDate = today
            _Concurrency.Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskScheduleDidChange)) { _ in
            _Concurrency.Task { await loadData() }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func goPrevWeek() {
        weekStart = DatabaseService.addDays(weekStart, days: -7)
        selectedDate = weekStart
        _Concurrency.Task { await loadData() }
    }

    private func goNextWeek() {
        weekStart = DatabaseService.addDays(weekStart, days: 7)
        selectedDate = weekStart
        _Concurrency.Task { await loadData() }
    }

    private func loadData() async {
        do {
            async let tasksResult = db.fetchTasksForWeek(weekStart)
            async let completionsResult = db.fetchCompletionsInRange(startDate: weekStart, endDate: DatabaseService.addDays(weekStart, days: 6))
            let (weekTasks, completions) = try await (tasksResult, completionsResult)
            tasks = weekTasks
            completedIds = Set(completions.map(\.taskId))
            completionIds = Dictionary(completions.map { ($0.taskId, $0.id) }, uniquingKeysWith: { first, _ in first })
        } catch {
            errorMessage = error.localizedDescription
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
        guard let completionId = completionIds[tw.task.id], !savingTaskIds.contains(tw.task.id) else { return }
        savingTaskIds.insert(tw.task.id)
        _ = withAnimation(reduceMotion ? nil : .snappy) { completedIds.remove(tw.task.id) }
        do {
            try await db.undoCompletion(id: completionId, taskBeforeCompletion: tw.task)
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
        } catch { errorMessage = error.localizedDescription }
        savingTaskIds.remove(task.task.id)
    }

    private func undoReschedule(_ task: TaskWithRoom) async {
        guard !savingTaskIds.contains(task.task.id) else { return }
        savingTaskIds.insert(task.task.id)
        do {
            try await db.restoreTaskSchedule(task.task)
            dismissRescheduleUndo()
        } catch { errorMessage = error.localizedDescription }
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
