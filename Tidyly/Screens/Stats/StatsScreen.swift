import SwiftUI

struct StatsScreen: View {
    @EnvironmentObject var db: DatabaseService
    @AppStorage("weekStartsMonday") private var weekStartsMonday = true
    @State private var completions: [Completion] = []
    @State private var tasks: [Task] = []
    @State private var rooms: [Room] = []
    @State private var loading = true
    @State private var refreshing = false

    private var today: String { DatabaseService.todayISO() }
    private var weekStart: String { DatabaseService.getWeekStart(weekStartsMonday: weekStartsMonday) }
    private var weekDates: [String] { DatabaseService.getWeekDates(weekStart) }
    private var fourWeeksAgo: String { DatabaseService.addDays(today, days: -28) }

    private var todayCompletions: Int { completions.filter { $0.completedAt == DatabaseService.dateOnlyFormatter.date(from: today) }.count }
    private var weekCompletions: Int { completions.filter { DatabaseService.dateOnlyFormatter.string(from: $0.completedAt) >= weekStart }.count }
    private var totalCompletions: Int { completions.count }

    private var totalMinutes: Int {
        completions.reduce(0) { sum, c in
            sum + (tasks.first { $0.id == c.taskId }?.estimatedMinutes ?? 0)
        }
    }

    private var streak: Int {
        let dates = Set(completions.map { DatabaseService.dateOnlyFormatter.string(from: $0.completedAt) })
        var count = 0
        var checkDate = today
        while dates.contains(checkDate) {
            count += 1
            checkDate = DatabaseService.addDays(checkDate, days: -1)
        }
        return count
    }

    private var bestStreak: Int {
        let sortedDates = Array(Set(completions.map { DatabaseService.dateOnlyFormatter.string(from: $0.completedAt) })).sorted()
        guard !sortedDates.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for i in 1..<sortedDates.count {
            if sortedDates[i] == DatabaseService.addDays(sortedDates[i - 1], days: 1) {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    private var weekBarData: [(date: String, count: Int)] {
        weekDates.map { date in
            (date, completions.filter { DatabaseService.dateOnlyFormatter.string(from: $0.completedAt) == date }.count)
        }
    }

    private var maxBarCount: Int { max(weekBarData.map { $0.count }.max() ?? 0, 1) }

    private var roomStats: [(room: Room, completions: Int)] {
        rooms.map { room in
            (room, completions.filter { $0.roomId == room.id }.count)
        }.sorted { $0.completions > $1.completions }
    }

    private var maxRoomCompletions: Int { max(roomStats.map { $0.completions }.max() ?? 0, 1) }

    private var completionRate: Int {
        guard !tasks.isEmpty else { return 0 }
        return Int(Double(totalCompletions) / Double(tasks.count) * 100)
    }

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingMd) {
                    // Streak cards
                    HStack(spacing: AppTheme.spacingMd) {
                        StreakCard(icon: "flame.fill", value: "\(streak)", label: "Day Streak", color: ColorAsset.warning.color)
                        StreakCard(icon: "trophy.fill", value: "\(bestStreak)", label: "Best Streak", color: ColorAsset.success.color)
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    // Stat cards
                    HStack(spacing: AppTheme.spacingMd) {
                        MiniStatCard(icon: "checkmark.circle.fill", value: "\(todayCompletions)", label: "Done Today", color: ColorAsset.primary.color)
                        MiniStatCard(icon: "calendar", value: "\(weekCompletions)", label: "This Week", color: ColorAsset.secondary.color)
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    HStack(spacing: AppTheme.spacingMd) {
                        MiniStatCard(icon: "arrow.up.right", value: "\(totalCompletions)", label: "Total", color: ColorAsset.accent.color)
                        MiniStatCard(icon: "clock", value: "\(totalMinutes / 60)h", label: "Time Spent", color: ColorAsset.success.color)
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    // Weekly bar chart
                    ChartCard(title: "This Week") {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(Array(weekBarData.enumerated()), id: \.offset) { idx, data in
                                let isToday = data.date == today
                                let heightPct = Double(data.count) / Double(maxBarCount)

                                VStack(spacing: 4) {
                                    if data.count > 0 {
                                        Text("\(data.count)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(isToday ? ColorAsset.primary.color : ColorAsset.textSecondary.color)
                                    }
                                    GeometryReader { geo in
                                        VStack {
                                            Spacer()
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isToday ? ColorAsset.primary.color : ColorAsset.primaryLight.color)
                                                .frame(width: 24, height: max(geo.size.height * heightPct, data.count > 0 ? 8 : 0))
                                        }
                                    }
                                    .frame(height: 100)

                                    Text(dayLabels[idx])
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isToday ? ColorAsset.primary.color : ColorAsset.textTertiary.color)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    // Room breakdown
                    ChartCard(title: "By Room") {
                        if roomStats.isEmpty {
                            Text("No rooms yet.")
                                .font(.system(size: 13))
                                .foregroundColor(ColorAsset.textTertiary.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.spacingXl)
                        } else {
                            VStack(spacing: AppTheme.spacingMd) {
                                ForEach(roomStats, id: \.room.id) { rs in
                                    HStack(spacing: AppTheme.spacingMd) {
                                        HStack(spacing: 6) {
                                            Text(rs.room.icon)
                                                .font(.system(size: 16))
                                            Text(rs.room.name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(ColorAsset.text.color)
                                        }
                                        .frame(width: 90, alignment: .leading)

                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: AppTheme.cornerMd)
                                                .fill(Color(hex: rs.room.color))
                                                .frame(width: geo.size.width * (Double(rs.completions) / Double(maxRoomCompletions)))
                                        }
                                        .frame(height: 24)
                                        .background(ColorAsset.surfaceAlt.color)
                                        .cornerRadius(AppTheme.cornerMd)

                                        Text("\(rs.completions)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(ColorAsset.text.color)
                                            .frame(minWidth: 24, alignment: .trailing)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    // Overall progress
                    ChartCard(title: "Overall Progress") {
                        HStack(spacing: AppTheme.spacingXl) {
                            VStack {
                                Text("\(completionRate)%")
                                    .font(.system(size: 40, weight: .heavy))
                                    .foregroundColor(ColorAsset.text.color)
                                Text("Completion Rate")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ColorAsset.textTertiary.color)
                            }

                            VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            completionRate >= 70 ? ColorAsset.success.color :
                                            completionRate >= 40 ? ColorAsset.warning.color :
                                            ColorAsset.error.color
                                        )
                                        .frame(width: geo.size.width * (Double(completionRate) / 100))
                                }
                                .frame(height: 12)
                                .background(ColorAsset.surfaceAlt.color)
                                .cornerRadius(6)

                                Text("\(totalCompletions) of \(tasks.count) tasks completed")
                                    .font(.system(size: 11))
                                    .foregroundColor(ColorAsset.textTertiary.color)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXl)

                    if completions.isEmpty && !loading {
                        EmptyStateView(icon: "arrow.up.right", title: "No data yet", subtitle: "Complete some tasks to see your stats here.")
                    }

                    Spacer().frame(height: 40)
                }
            }
            .navigationTitle("Statistics")
            .background(ColorAsset.background.color.ignoresSafeArea())
            .refreshable { await loadData() }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .taskScheduleDidChange)) { _ in
            _Concurrency.Task { await loadData() }
        }
    }

    private func loadData() async {
        do {
            async let comps = db.fetchCompletionsInRange(startDate: fourWeeksAgo, endDate: today)
            async let allTasks = db.fetchAllTasks()
            async let allRooms = db.fetchRooms()
            let (c, t, r) = try await (comps, allTasks, allRooms)
            completions = c
            tasks = t
            rooms = r
        } catch {
            print("Load error: \(error)")
        }
        loading = false
        refreshing = false
    }
}

private struct StreakCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: AppTheme.spacingSm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(ColorAsset.text.color)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ColorAsset.textTertiary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.spacingXl)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerXl)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerXl).stroke(ColorAsset.border.color, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

private struct MiniStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: AppTheme.spacingSm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(ColorAsset.text.color)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ColorAsset.textTertiary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.spacingLg)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingLg) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(ColorAsset.text.color)
            content()
        }
        .padding(AppTheme.spacingXl)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerXl)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerXl).stroke(ColorAsset.border.color, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}
