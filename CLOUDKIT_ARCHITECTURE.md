# CloudKit household architecture

Tidyly uses one custom CloudKit record zone per household. The owner stores the
zone in their private database and shares the whole zone with a `CKShare`.
Participants access the same records through their shared database. CloudKit's
participants and permissions are authoritative; Tidyly does not maintain a
second membership database.

## Boundaries

Cloud-shared data: household name, rooms, tasks, completions, activity events,
and the household week-start preference.

Device-local data: notification permission and requests, default reminder time,
overdue follow-ups, room/task reminder overrides, dark mode, widget snapshots,
undo UI, migration checkpoints, sync tokens, and errors.

The widget remains App Group-only. After remote changes are imported, the main
app republishes its snapshot and reconciles local notifications.

## Identity and records

Every domain record keeps its existing UUID. CloudKit record names are the UUID
strings, making retries idempotent. All records carry a household UUID and
mutation UUID. Rooms and tasks use stable ordering keys. Completions and activity
events are append-only; undo is represented by a compensating event.

Physical deletion is delayed. A tombstone wins over edits to the deleted object,
while immutable activity snapshots remain. Duplicate append-only records are
discarded by UUID, never timestamp.

## Local migration

The current SwiftData store remains the offline source during migration. A
device-local checkpoint records a stable household ID, migration ID, phase, and
the uploaded record IDs. Migration creates a private zone, uploads the household
and existing records in retryable batches, verifies them, and only then enables
normal synchronization. Interrupted work resumes with the same IDs.

Accepting an invitation never overwrites existing local data. A device with local
content must keep it as a separate household until the user explicitly chooses a
future merge or migration action.

## Synchronization

SwiftData managed CloudKit synchronization stays disabled. It synchronizes a
person's private database but does not implement shared-zone invitations and
participant access. Focused CloudKit services push and fetch records while
SwiftData remains the offline cache.

Services are split into account monitoring, household sharing, migration,
synchronization, status/error translation, widget publishing, and reminder
reconciliation. Views never issue CloudKit operations directly.

## Release gates

Before enabling household creation in a beta build:

1. Register `iCloud.com.tidyly.jonesweb.club` for team `VS4RFZ5734`.
2. Verify regenerated profiles contain App Group, CloudKit, and remote-notification capabilities.
3. Initialize and inspect the development CloudKit schema.
4. Test migration without data loss on an existing device store.
5. Test invitation acceptance and mutations with two different iCloud accounts.
6. Promote the reviewed additive schema to production before TestFlight use.

