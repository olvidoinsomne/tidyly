import SwiftUI

struct SearchScreen: View {
    @EnvironmentObject private var db: DatabaseService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tasks: [TaskWithRoom] = []
    @State private var rooms: [Room] = []
    @State private var completedToday: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedRoomId: UUID?
    @State private var selectedPriority: Priority?
    @State private var dueFilter: DueFilter = .all
    @State private var timeFilter: TimeFilter = .all
    @State private var statusFilter: StatusFilter = .all
    @State private var showingFilters = false
    @State private var loading = true
    @State private var savingTaskIds: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var undoItem: (task: TaskWithRoom, completionId: UUID)?

    private var filteredTasks: [TaskWithRoom] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { item in
            let task = item.task
            let due = DatabaseService.dateOnlyFormatter.string(from: task.nextDueAt)
            let isComplete = completedToday.contains(task.id)
            return (query.isEmpty || task.title.localizedStandardContains(query) || item.room.name.localizedStandardContains(query))
                && (selectedRoomId == nil || task.roomId == selectedRoomId)
                && (selectedPriority == nil || task.priority == selectedPriority)
                && dueFilter.includes(due)
                && timeFilter.includes(task.estimatedMinutes)
                && statusFilter.includes(isCompletedToday: isComplete)
        }
    }

    private var activeFilterCount: Int {
        [selectedRoomId != nil, selectedPriority != nil, dueFilter != .all, timeFilter != .all, statusFilter != .all].filter { $0 }.count
    }

    private var filterIconName: String {
        activeFilterCount == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    private var filterAccessibilityLabel: String {
        activeFilterCount == 0 ? "Filters" : "Filters, \(activeFilterCount) active"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: AppTheme.spacingLg) {
                if activeFilterCount > 0 { activeFilters }

                Text(resultSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorAsset.textSecondary.color)
                    .padding(.horizontal, AppTheme.spacingXl)
                    .accessibilityLabel(resultSummary)

                if loading {
                    ProgressView("Loading tasks…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppTheme.spacingXxxl)
                } else if filteredTasks.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No matching tasks", subtitle: "Try changing your search or clearing some filters.")
                        .padding(.top, AppTheme.spacingXxl)
                } else {
                    LazyVStack(spacing: AppTheme.spacingMd) {
                        ForEach(filteredTasks) { item in
                            let isCompleted = completedToday.contains(item.task.id)
                            TaskCardView(
                                taskWithRoom: item,
                                isCompleted: isCompleted,
                                isSaving: savingTaskIds.contains(item.task.id),
                                onComplete: isCompleted ? nil : { beginComplete(item) },
                                onReschedule: isCompleted ? nil : { action in beginReschedule(item, action: action) }
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)
                }
            }
            .padding(.vertical, AppTheme.spacingMd)
        }
        .navigationTitle("Search")
        .background(ColorAsset.background.color.ignoresSafeArea())
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tasks or rooms")
        .navigationBarItems(trailing:
            Button { showingFilters = true } label: {
                Image(systemName: filterIconName)
            }
            .accessibilityLabel(filterAccessibilityLabel)
        )
        .safeAreaInset(edge: .bottom) {
            if let undoItem {
                CompletionUndoBanner(taskTitle: undoItem.task.task.title, isSaving: savingTaskIds.contains(undoItem.task.task.id)) {
                    _Concurrency.Task { await undoCompletion(undoItem.task, completionId: undoItem.completionId) }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingFilters) { filterSheet }
        .refreshable { await loadData() }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .taskScheduleDidChange)) { _ in
            _Concurrency.Task<Void, Never> { await loadData() }
        }
        .alert("Couldn’t Update Task", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private var resultSummary: String {
        "\(filteredTasks.count) \(filteredTasks.count == 1 ? "task" : "tasks")"
    }

    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacingSm) {
                if let selectedRoomId, let room = rooms.first(where: { $0.id == selectedRoomId }) {
                    FilterChip(label: "\(room.icon) \(room.name)") { self.selectedRoomId = nil }
                }
                if let selectedPriority { FilterChip(label: "\(selectedPriority.label) priority") { self.selectedPriority = nil } }
                if dueFilter != .all { FilterChip(label: dueFilter.label) { dueFilter = .all } }
                if timeFilter != .all { FilterChip(label: timeFilter.label) { timeFilter = .all } }
                if statusFilter != .all { FilterChip(label: statusFilter.label) { statusFilter = .all } }
                Button("Clear All") { resetFilters() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorAsset.primary.color)
            }
            .padding(.horizontal, AppTheme.spacingXl)
        }
        .accessibilityLabel("Active filters")
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Picker("Room", selection: $selectedRoomId) {
                    Text("All rooms").tag(nil as UUID?)
                    ForEach(rooms) { Text("\($0.icon) \($0.name)").tag($0.id as UUID?) }
                }
                Picker("Priority", selection: $selectedPriority) {
                    Text("All priorities").tag(nil as Priority?)
                    ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0 as Priority?) }
                }
                Picker("Due", selection: $dueFilter) { ForEach(DueFilter.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker("Estimated time", selection: $timeFilter) { ForEach(TimeFilter.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker("Status", selection: $statusFilter) { ForEach(StatusFilter.allCases, id: \.self) { Text($0.label).tag($0) } }
                if activeFilterCount > 0 { Button("Reset All Filters", role: .destructive) { resetFilters() } }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func resetFilters() {
        selectedRoomId = nil
        selectedPriority = nil
        dueFilter = .all
        timeFilter = .all
        statusFilter = .all
    }

    private func loadData() async {
        do {
            let today = DatabaseService.todayISO()
            async let tasksResult = db.fetchAllTasksWithRooms()
            async let roomsResult = db.fetchRooms()
            async let completionsResult = db.fetchCompletionsInRange(startDate: today, endDate: today)
            let (allTasks, allRooms, completions) = try await (tasksResult, roomsResult, completionsResult)
            tasks = allTasks
            rooms = allRooms
            completedToday = Set(completions.map(\.taskId))
        } catch { errorMessage = error.localizedDescription }
        loading = false
    }

    private func beginComplete(_ item: TaskWithRoom) {
        _Concurrency.Task<Void, Never> { await complete(item) }
    }

    private func beginReschedule(_ item: TaskWithRoom, action: TaskRescheduleAction) {
        _Concurrency.Task<Void, Never> { await reschedule(item, action: action) }
    }

    private func complete(_ item: TaskWithRoom) async {
        guard !savingTaskIds.contains(item.task.id) else { return }
        savingTaskIds.insert(item.task.id)
        do {
            let completion = try await db.completeTask(item.task)
            completedToday.insert(item.task.id)
            undoItem = (item, completion.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await loadData()
        } catch { errorMessage = error.localizedDescription }
        savingTaskIds.remove(item.task.id)
    }

    private func undoCompletion(_ item: TaskWithRoom, completionId: UUID) async {
        guard !savingTaskIds.contains(item.task.id) else { return }
        savingTaskIds.insert(item.task.id)
        do {
            try await db.undoCompletion(id: completionId, taskBeforeCompletion: item.task)
            undoItem = nil
            await loadData()
        } catch { errorMessage = error.localizedDescription }
        savingTaskIds.remove(item.task.id)
    }

    private func reschedule(_ item: TaskWithRoom, action: TaskRescheduleAction) async {
        guard !savingTaskIds.contains(item.task.id) else { return }
        savingTaskIds.insert(item.task.id)
        do { try await db.rescheduleTask(item.task, action: action); await loadData() }
        catch { errorMessage = error.localizedDescription }
        savingTaskIds.remove(item.task.id)
    }
}

@MainActor private enum DueFilter: CaseIterable { case all, overdue, today
    var label: String { switch self { case .all: "Any due date"; case .overdue: "Overdue"; case .today: "Due today" } }
    func includes(_ due: String) -> Bool { switch self { case .all: true; case .overdue: DatabaseService.daysUntil(due) < 0; case .today: DatabaseService.daysUntil(due) == 0 } }
}

private enum TimeFilter: CaseIterable { case all, fiveOrLess, fifteenOrLess, thirtyOrLess, overThirty
    var label: String { switch self { case .all: "Any duration"; case .fiveOrLess: "5 min or less"; case .fifteenOrLess: "15 min or less"; case .thirtyOrLess: "30 min or less"; case .overThirty: "Over 30 min" } }
    func includes(_ minutes: Int) -> Bool { switch self { case .all: true; case .fiveOrLess: minutes <= 5; case .fifteenOrLess: minutes <= 15; case .thirtyOrLess: minutes <= 30; case .overThirty: minutes > 30 } }
}

private enum StatusFilter: CaseIterable { case all, pending, completedToday
    var label: String { switch self { case .all: "Any status"; case .pending: "Pending"; case .completedToday: "Completed today" } }
    func includes(isCompletedToday: Bool) -> Bool { switch self { case .all: true; case .pending: !isCompletedToday; case .completedToday: isCompletedToday } }
}

private struct FilterChip: View {
    let label: String
    let remove: () -> Void
    var body: some View {
        Button(action: remove) {
            HStack(spacing: AppTheme.spacingXs) {
                Text(label)
                Image(systemName: "xmark.circle.fill").accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(ColorAsset.primary.color)
            .padding(.horizontal, AppTheme.spacingMd)
            .padding(.vertical, AppTheme.spacingSm)
            .background(ColorAsset.primaryLight.color)
            .clipShape(Capsule())
        }
        .accessibilityLabel("Remove \(label) filter")
    }
}
