# Tidyly
<img src="Tidyly/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="Tidyly Logo" width="400">

Tidyly is a native SwiftUI home-care app for organizing recurring cleaning tasks by room. The application is local-first: rooms, tasks, completion records, activity history, settings, and reminder preferences are stored on the device with SwiftData.

The current primary product is the iOS application. No CloudKit container, Supabase client, Firebase integration, account system, or other remote synchronization backend is enabled. Each installation therefore has its own independent data.

## Current status

- Native SwiftUI application targeting iOS 17
- Swift 5.9 and SwiftData
- Xcode project generated from `project.yml` with XcodeGen
- Primary scheme: `Tidyly_iOS`
- App bundle identifier: `com.tidyly.jonesweb.club`
- Widget bundle identifier: `com.tidyly.jonesweb.club.widget`
- Shared App Group: `group.com.tidyly.jonesweb.club`
- Marketing version: `1.0.0`
- Current project version: `1`
- Local notifications managed with `UserNotifications`
- CloudKit synchronization disabled
- Remote multi-user synchronization intentionally not implemented

The project definition also declares a macOS platform, but current development and verification are focused on iOS. The application contains iOS-specific interactions and should not be considered a tested macOS release without a separate compatibility pass.

## Product areas

### Today

The Today tab displays tasks whose due date is today or overdue. It includes:

- Remaining-time, overdue, and completed summaries
- Daily completion progress
- One-tap task completion
- Optimistic completion animations and success haptics
- Completed-task sections
- Six-second Undo opportunities
- Task rescheduling actions
- A shortcut to global Search
- Task creation

Completion and rescheduling operations are save-locked to prevent repeated mutations. Failed persistence operations roll the visible state back and display an error.

### Rooms

Rooms can be created, edited, reordered, and deleted. Each room has:

- A name, emoji icon, and color
- A stable sort order
- Its own tasks and progress summary
- A room-wide reminder switch

New-room addition suggests common starter tasks based on the room name. Users can select individual suggestions, select all suggestions, or clear the selection. The room and selected starter tasks are inserted in one SwiftData save.

Deleting a room deletes its live tasks and completion records. Immutable activity-event snapshots remain available so past actions are still understandable.

### Tasks

Tasks support:

- Room assignment
- Recurring frequency
- Low, medium, or high priority
- Estimated completion time
- Next due date
- Last completion date
- Completion and Undo
- Editing and deletion
- Per-task reminder enablement
- Optional per-task reminder time

Completing a recurring task records a completion and calculates its next due date from the completion date. Undo restores the exact previous `lastDoneAt` and `nextDueAt` values.

Rescheduling is intentionally separate from completion. It never changes `lastDoneAt` or creates a completion record. Available actions are:

- **Do Tomorrow** — moves the task to tomorrow
- **Skip This Time** — advances one recurrence interval
- **Choose Date** — assigns a custom due date

Each action offers a short Undo opportunity that restores the original schedule.

### Schedule

The Schedule tab provides weekly navigation and a selectable seven-day calendar. It shows pending and completed tasks for the selected date and supports the same completion, Undo, and rescheduling behavior as Today and Rooms.

### Search and smart filters

Global Search is available from the magnifying-glass button on Today. It searches task and room names and can combine filters using AND semantics:

- Room
- Priority
- Overdue
- Due today
- Estimated time
- Pending
- Completed today

Active filters appear as removable chips and can be reset together. Results reuse the standard task-card component and allow completion, Undo, and rescheduling.

Filtering currently runs in memory over the local SwiftData result set. This avoids repeated persistence queries while the user changes search text and filters.

### Activity history

Activity is available under **Settings → Data → Activity**. It displays an accessible chronological timeline of:

- Task completion
- Completion Undo
- Postponement until tomorrow
- Skipped occurrences
- Custom-date rescheduling
- Rescheduling Undo

Every activity event stores task and room identifiers, snapshot names, event type, timestamp, previous and resulting due dates, previous and resulting completion state, and a related completion identifier when applicable.

Events are inserted in the same SwiftData save as their corresponding task mutation. Activity history is intentionally retained when a task or room is deleted. The snapshot fields keep historical entries readable without depending on live records.

### Statistics

The Stats tab derives its values from local completion records. It currently includes:

- Current and best streaks
- Completions today and during the current week
- Completion totals from the loaded 28-day window
- Estimated time spent
- Weekly completion chart
- Completion breakdown by room
- Overall completion rate

Statistics are currently calculated in memory. Activity events are structured for future statistics work but are not yet used as the main Stats data source.

### Reminders

Settings provides:

- Global notification enablement
- Notification-permission status
- A configurable default reminder time
- Optional overdue follow-up notifications

Task and room editors provide narrower controls:

- Disable all reminders for a room
- Disable reminders for an individual task
- Override the default time for an individual task

`NotificationService` owns permission handling and pending-notification reconciliation. After completion, Undo, rescheduling, task edits, task deletion, or room deletion, Tidyly removes its pending requests and recreates the eligible set. Stable task-based identifiers prevent duplicates.

iOS limits the number of pending local notifications. Tidyly prioritizes the nearest due tasks and schedules up to 60 tasks without follow-ups or 30 tasks when follow-ups are enabled. Reminder failures and denied permission are surfaced in the application.

Notifications are local to each device. They do not provide background data synchronization or multi-user coordination.

### Settings and data

Settings currently includes:

- Household name
- Notification preferences
- Dark mode
- Monday or Sunday week starts
- Reminder configuration
- Activity navigation
- Data export action
- Clear All Data confirmation UI

Current limitations:

- Export serializes a subset of rooms, tasks, and completions to a temporary JSON file and logs its path; it does not yet present a share sheet.
- Clear All Data presents confirmation UI, but the destructive database operation is not implemented.
- Several secondary loading failures are logged rather than shown with dedicated recovery UI.

## Home Screen widget

The `TidylyWidget` WidgetKit extension supports small and medium families. It displays:

- Remaining task count
- Completed-task progress
- Estimated remaining time
- Up to three due or overdue tasks

The widget reads a JSON snapshot from shared App Group `UserDefaults`. The main app republishes the snapshot after relevant persistence mutations and asks WidgetKit to reload its timeline. The widget also refreshes on a 30-minute timeline policy.

Tapping the widget opens `tidyly://today`, which selects the Today tab.

The widget intentionally uses explicit dark foreground colors against its light gradient background so text remains legible in system appearance modes.

## Persistence architecture

`DatabaseService` is a `@MainActor` observable object that owns the SwiftData `ModelContainer` and its main context. The store uses a named local configuration with CloudKit explicitly disabled.

Stored SwiftData models:

- `StoredRoom`
- `StoredTask`
- `StoredCompletion`
- `StoredActivityEvent`
- `StoredSettings`

UI-facing value types are kept in `Models.swift` and mapped from the stored models by `DatabaseService`. Views access the shared service through SwiftUI’s environment.

There is currently no user identity, household membership model, server merge policy, remote change feed, or cross-device conflict resolution.

## Accessibility

The application includes accessibility labels for primary task, Undo, filter, widget, and activity interactions. Task feedback uses VoiceOver announcements where appropriate. Completion and Undo transitions respect Reduce Motion. Activity and Search layouts use semantic text styles where implemented, and task priority is communicated with text as well as color.

## Project structure

```text
Tidyly/
├── README.md
├── project.yml
├── Tidyly.xcodeproj/       # Generated by XcodeGen
├── Tidyly/
│   ├── TidylyApp.swift
│   ├── Assets.xcassets/
│   ├── Components/
│   ├── Models/
│   ├── Screens/
│   │   ├── Activity/
│   │   ├── Rooms/
│   │   ├── Schedule/
│   │   ├── Search/
│   │   ├── Settings/
│   │   ├── Stats/
│   │   └── Today/
│   ├── Services/
│   ├── Theme/
│   └── Tidyly.entitlements
└── TidylyWidget/
    ├── Info.plist
    ├── TidylyWidget.swift
    └── TidylyWidget.entitlements
```

The repository root still contains configuration files from the earlier Expo implementation. The tracked Expo source directories are currently deleted, and the SwiftUI application is the active implementation.

## Building

Requirements:

- macOS with Xcode
- XcodeGen
- An Apple development team for signed device installation

Generate the project whenever `project.yml` changes or source files are added:

```bash
cd /Users/tim/Documents/Tidyly
xcodegen generate
```

Open the project:

```bash
open Tidyly.xcodeproj
```

Select the `Tidyly_iOS` scheme and an iOS 17-or-later destination.

Unsigned verification build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project Tidyly.xcodeproj \
  -scheme Tidyly_iOS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/tidyly-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## XcodeGen and signing notes

`project.yml` is the project source of truth. Do not rely on manual changes made only inside the generated `.xcodeproj`.

The following settings must remain declared in `project.yml`:

- The application and widget App Group entitlement
- The widget `NSExtension` dictionary
- Widget embedding in the iOS application
- The `tidyly` URL scheme

XcodeGen can regenerate plist and entitlement files. Removing these declarations from `project.yml` can silently break widget discovery or shared snapshot access.

Current signing configuration:

- Automatic signing
- Development team `VS4RFZ5734`
- App bundle ID `com.tidyly.jonesweb.club`
- Widget bundle ID `com.tidyly.jonesweb.club.widget`

## Verification status

As of July 19, 2026:

- `xcodegen generate` succeeds from the repository root.
- The `Tidyly_iOS` generic-device build succeeds.
- A signed application and widget build succeeds.
- The app installs and launches on test devices.
- The expanded SwiftData schema for activity and reminders opens on that device without a migration crash.

## Next likely work

- Complete the data-export sharing flow
- Implement Clear All Data
- Rework Stats to use activity events and clearer time ranges
- Audit and either support or remove the declared macOS target
