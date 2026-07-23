import SwiftUI

extension Notification.Name {
    static let taskScheduleDidChange = Notification.Name("taskScheduleDidChange")
}

enum TaskRescheduleAction {
    case tomorrow
    case skip
    case custom(Date)

    func nextDueDate(for task: Task) -> Date {
        let calendar = Calendar.current
        switch self {
        case .tomorrow:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        case .skip:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: task.frequencyDays, to: task.nextDueAt) ?? task.nextDueAt)
        case .custom(let date):
            return calendar.startOfDay(for: date)
        }
    }

    @MainActor func feedbackMessage(for task: Task) -> String {
        switch self {
        case .tomorrow: return "\(task.title) moved to tomorrow"
        case .skip: return "Skipped this occurrence of \(task.title)"
        case .custom(let date): return "\(task.title) moved to \(DatabaseService.monthDayFormatter.string(from: date))"
        }
    }
}

struct TaskCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var supabaseConnection: SupabaseConnectionService

    let taskWithRoom: TaskWithRoom
    var isCompleted: Bool = false
    var isSaving: Bool = false
    var onComplete: (() -> Void)? = nil
    var onUndo: (() -> Void)? = nil
    var onReschedule: ((TaskRescheduleAction) -> Void)? = nil

    private var task: Task { taskWithRoom.task }
    private var room: Room { taskWithRoom.room }
    private var priority: Priority { task.priority }

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
                        completionControl
                        title
                        Spacer(minLength: AppTheme.spacingSm)
                        trailingAction
                    }
                    VStack(alignment: .leading, spacing: AppTheme.spacingSm) {
                        metadata
                        if !isCompleted { dueBadge }
                    }
                }
            } else {
                HStack(spacing: AppTheme.spacingMd) {
                    completionControl
                    VStack(alignment: .leading, spacing: AppTheme.spacingXs) {
                        title
                        metadata
                    }
                    Spacer(minLength: AppTheme.spacingSm)
                    if !isCompleted { dueBadge }
                    trailingAction
                }
            }
        }
        .padding(AppTheme.spacingLg)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerLg)
                .stroke(ColorAsset.border.color, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        .opacity(isCompleted ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var completionControl: some View {
        if isCompleted {
            ZStack {
                Circle()
                    .fill(ColorAsset.success.color)
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
        } else {
            Button(action: { onComplete?() }) {
                ZStack {
                    Circle()
                        .strokeBorder(ColorAsset.borderDark.color, lineWidth: 2)
                    if isSaving { ProgressView().controlSize(.small) }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isSaving || onComplete == nil)
            .accessibilityLabel("Complete \(task.title)")
            .accessibilityHint("Marks this task complete")
        }
    }

    private var title: some View {
        Text(task.title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(isCompleted ? ColorAsset.textTertiary.color : ColorAsset.text.color)
            .strikethrough(isCompleted)
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
            Text(room.icon)
            Text(room.name)
                .foregroundColor(Color(hex: room.color))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: room.color).opacity(0.12))
        .cornerRadius(8)

        if !isCompleted {
            if let membershipId = task.assignedMembershipId,
               let member = supabaseConnection.householdMembers.first(where: { $0.id == membershipId }) {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .accessibilityHidden(true)
                    Text(member.displayName ?? "Tidyly member")
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorAsset.primary.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ColorAsset.primary.color.opacity(0.12))
                .cornerRadius(8)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(priority.color.color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(priority.label)
                    .foregroundColor(priority.color.color)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priority.color.color.opacity(0.12))
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
        } else {
            Text("Done today")
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorAsset.success.color)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var dueBadge: some View {
        Text(DatabaseService.formatRelativeDate(dueDateStr))
            .font(.caption.weight(.semibold))
            .foregroundColor(isOverdue ? ColorAsset.error.color : isDueToday ? ColorAsset.primary.color : ColorAsset.textSecondary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isOverdue ? ColorAsset.error.color : isDueToday ? ColorAsset.primary.color : ColorAsset.surfaceAlt.color).opacity(0.12)
            )
            .cornerRadius(10)
    }

    @ViewBuilder
    private var trailingAction: some View {
        if !isCompleted, let onReschedule {
            TaskRescheduleMenu(task: task, isSaving: isSaving, onReschedule: onReschedule)
        }

        if isCompleted, let onUndo {
            Button(action: onUndo) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body)
                    .foregroundColor(ColorAsset.textTertiary.color)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel("Undo completion for \(task.title)")
        }
    }
}

struct TaskRescheduleMenu: View {
    let task: Task
    let isSaving: Bool
    let onReschedule: (TaskRescheduleAction) -> Void
    @State private var showCustomDate = false
    @State private var customDate = Date()

    var body: some View {
        Menu {
            Button { onReschedule(.tomorrow) } label: {
                Label("Do Tomorrow", systemImage: "sunrise")
            }
            Button { onReschedule(.skip) } label: {
                Label("Skip This Time", systemImage: "forward")
            }
            Button { showCustomDate = true } label: {
                Label("Choose Date…", systemImage: "calendar")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(ColorAsset.textSecondary.color)
                .frame(width: 44, height: 44)
        }
        .disabled(isSaving)
        .accessibilityLabel("More actions for \(task.title)")
        .sheet(isPresented: $showCustomDate) {
            NavigationStack {
                VStack(alignment: .leading, spacing: AppTheme.spacingLg) {
                    Text("Set the next due date directly. This won’t mark the task complete or change its history.")
                        .font(.system(size: 14))
                        .foregroundColor(ColorAsset.textSecondary.color)
                    DatePicker("Next due date", selection: $customDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Spacer()
                }
                .padding(AppTheme.spacingXl)
                .navigationTitle("Choose Due Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCustomDate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Set Date") {
                            let date = customDate
                            showCustomDate = false
                            onReschedule(.custom(date))
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct ActionUndoBanner: View {
    let message: String
    let isSaving: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.spacingMd) {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundColor(ColorAsset.primary.color)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.system(size: 14, weight: .bold))
                .disabled(isSaving)
        }
        .padding(AppTheme.spacingLg)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, AppTheme.spacingXl)
        .padding(.bottom, AppTheme.spacingMd)
        .accessibilityElement(children: .contain)
    }
}

struct CompletionUndoBanner: View {
    let taskTitle: String
    let isSaving: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.spacingMd) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(ColorAsset.success.color)
            Text("\(taskTitle) completed")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.system(size: 14, weight: .bold))
                .disabled(isSaving)
        }
        .padding(AppTheme.spacingLg)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerLg).stroke(ColorAsset.border.color))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, AppTheme.spacingXl)
        .padding(.bottom, AppTheme.spacingMd)
        .accessibilityElement(children: .contain)
    }
}
