import SwiftUI

struct ActivityScreen: View {
    @EnvironmentObject private var db: DatabaseService
    @State private var events: [ActivityEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var groupedEvents: [(date: Date, events: [ActivityEvent])] {
        let calendar = Calendar.current
        return Dictionary(grouping: events) { calendar.startOfDay(for: $0.timestamp) }
            .map { (date: $0.key, events: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading activity…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppTheme.spacingXxxl)
            } else if events.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No activity yet",
                    subtitle: "Completed and rescheduled tasks will appear here."
                )
                .padding(.top, AppTheme.spacingXxxl)
            } else {
                LazyVStack(alignment: .leading, spacing: AppTheme.spacingXl) {
                    ForEach(groupedEvents, id: \.date) { group in
                        VStack(alignment: .leading, spacing: AppTheme.spacingMd) {
                            Text(group.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                .font(.headline)
                                .foregroundColor(ColorAsset.textSecondary.color)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(group.events) { event in
                                ActivityEventRow(event: event)
                            }
                        }
                    }
                }
                .padding(AppTheme.spacingXl)
            }
        }
        .navigationTitle("Activity")
        .background(ColorAsset.background.color.ignoresSafeArea())
        .refreshable { await loadEvents() }
        .task { await loadEvents() }
        .alert("Couldn’t Load Activity", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func loadEvents() async {
        do { events = try await db.fetchActivityEvents() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct ActivityEventRow: View {
    let event: ActivityEvent

    private var presentation: (icon: String, title: String, color: Color) {
        switch event.type {
        case .completed: return ("checkmark.circle.fill", "Completed", ColorAsset.success.color)
        case .completionUndone: return ("arrow.uturn.backward.circle.fill", "Completion undone", ColorAsset.textSecondary.color)
        case .postponed: return ("sunrise.fill", "Postponed until tomorrow", ColorAsset.warning.color)
        case .skipped: return ("forward.end.circle.fill", "Skipped this time", ColorAsset.secondary.color)
        case .rescheduled: return ("calendar.badge.clock", "Rescheduled", ColorAsset.primary.color)
        case .rescheduleUndone: return ("arrow.uturn.backward.circle.fill", "Reschedule undone", ColorAsset.textSecondary.color)
        }
    }

    private var dateDetail: String? {
        guard event.type != .completed else { return nil }
        if let resulting = event.resultingDueDate {
            return "Due \(resulting.formatted(date: .abbreviated, time: .omitted))"
        }
        return nil
    }

    private var accessibilityText: String {
        [presentation.title, event.taskTitle, event.roomName, dateDetail, event.timestamp.formatted(date: .omitted, time: .shortened)]
            .compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingMd) {
            Image(systemName: presentation.icon)
                .font(.title3)
                .foregroundColor(presentation.color)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacingXs) {
                Text(presentation.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(ColorAsset.text.color)
                Text(event.taskTitle)
                    .font(.body)
                    .foregroundColor(ColorAsset.text.color)
                Text([event.roomName, dateDetail].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundColor(ColorAsset.textSecondary.color)
                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(ColorAsset.textTertiary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.spacingLg)
        .background(ColorAsset.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerLg))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
