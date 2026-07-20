import SwiftUI
import WidgetKit

struct TidylyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TidylyWidgetSnapshot
}

struct TidylyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TidylyWidgetEntry { TidylyWidgetEntry(date: Date(), snapshot: sample) }

    func getSnapshot(in context: Context, completion: @escaping (TidylyWidgetEntry) -> Void) {
        completion(TidylyWidgetEntry(date: Date(), snapshot: context.isPreview ? sample : TidylyWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TidylyWidgetEntry>) -> Void) {
        let entry = TidylyWidgetEntry(date: Date(), snapshot: TidylyWidgetStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }

    private var sample: TidylyWidgetSnapshot {
        TidylyWidgetSnapshot(generatedAt: Date(), remainingCount: 3, completedCount: 2, remainingMinutes: 35, tasks: [
            TidylyWidgetTask(id: UUID(), title: "Wipe countertops", roomName: "Kitchen", roomIcon: "🍳", isOverdue: true),
            TidylyWidgetTask(id: UUID(), title: "Vacuum the floor", roomName: "Living Room", roomIcon: "🛋️", isOverdue: false)
        ])
    }
}

struct TidylyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TidylyWidgetEntry
    private let primaryText = Color(red: 0.08, green: 0.12, blue: 0.18)
    private let secondaryText = Color(red: 0.28, green: 0.33, blue: 0.40)

    var body: some View {
        Group { family == .systemSmall ? AnyView(smallView) : AnyView(mediumView) }
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.94, green: 0.97, blue: 1), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(URL(string: "tidyly://today"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tidyly", systemImage: "checklist").font(.headline).foregroundStyle(Color(red: 0.08, green: 0.32, blue: 0.72))
            Spacer()
            Text(entry.snapshot.remainingCount == 0 ? "All done!" : "\(entry.snapshot.remainingCount) left")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(primaryText)
            Text(entry.snapshot.remainingCount == 0 ? "Your home is on track" : "About \(entry.snapshot.remainingMinutes) min")
                .font(.caption).foregroundStyle(secondaryText)
            ProgressView(value: entry.snapshot.progress).tint(.blue)
                .accessibilityLabel("Today's progress")
                .accessibilityValue("\(Int(entry.snapshot.progress * 100)) percent")
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Today", systemImage: "checklist").font(.headline).foregroundStyle(Color(red: 0.08, green: 0.32, blue: 0.72))
                Text("\(entry.snapshot.remainingCount)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(primaryText)
                Text(entry.snapshot.remainingCount == 1 ? "task remaining" : "tasks remaining").font(.caption).foregroundStyle(secondaryText)
                ProgressView(value: entry.snapshot.progress).tint(.blue)
                Text("\(entry.snapshot.completedCount) done · \(entry.snapshot.remainingMinutes) min left").font(.caption2).foregroundStyle(secondaryText)
            }
            .frame(width: 120, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                if entry.snapshot.tasks.isEmpty {
                    Spacer()
                    Label("Nothing due", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    Text("Enjoy your clean home.").font(.caption).foregroundStyle(secondaryText)
                    Spacer()
                } else {
                    ForEach(entry.snapshot.tasks.prefix(3)) { task in
                        HStack(spacing: 7) {
                            Text(task.roomIcon)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title).font(.caption.weight(.semibold)).foregroundStyle(primaryText).lineLimit(1)
                                Text(task.isOverdue ? "Overdue · \(task.roomName)" : task.roomName)
                                    .font(.caption2)
                                    .foregroundStyle(task.isOverdue ? Color(red: 0.72, green: 0.10, blue: 0.10) : secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct TidylyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TidylyTodayWidget", provider: TidylyWidgetProvider()) { TidylyWidgetView(entry: $0) }
            .configurationDisplayName("Tidyly Today")
            .description("See today’s cleaning progress and what’s next.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
