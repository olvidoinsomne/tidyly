# ADR-001: Shared household backend architecture

- Status: Accepted
- Date: 2026-07-22
- App baseline: Tidyly 1.0.7

## Context

Tidyly is currently a native SwiftUI application backed by a local SwiftData
store. Its CloudKit prototype shares a record zone and periodically merges
rooms and tasks, but the local database remains operationally authoritative.
That prototype does not provide the account, membership, invitation,
authorization, assignment, and audit semantics required for a true shared
household.

Tidyly is expected to support Android and web clients in the future. The shared
domain and identity model therefore cannot depend on CloudKit, iCloud identity,
SwiftData, or other Apple-only facilities.

## Decision

Tidyly will use a dedicated, server-authoritative backend. The initial choice
is Supabase:

- Supabase Auth, with native Sign in with Apple as the first identity provider.
- PostgreSQL as the authoritative shared data store.
- PostgreSQL row-level security (RLS) for household isolation and authorization.
- Transactional database functions for invitation acceptance, membership
  changes, ownership transfer, task completion, completion reversal, and other
  multi-row invariants.
- Supabase Realtime as change notification, paired with cursor-based
  reconciliation so realtime delivery is not the sole source of correctness.
- SwiftData as the iOS offline cache and durable mutation outbox, not the source
  of truth.

Android and web clients will use platform-appropriate local caches while
sharing the same backend schema, authorization rules, API semantics, stable
UUID identifiers, and idempotent mutation protocol.

CloudKit will not be extended into the long-term household backend. Existing
CloudKit and SwiftData data will remain migration sources until their retirement
is explicitly planned and verified.

## Product decisions

### Household membership

- A user may have zero or one active household membership.
- Historical ended memberships are retained for attribution and auditing.
- A user must leave their current household before accepting another
  household invitation.
- An Owner must transfer ownership or delete the household before leaving.
- The initial roles are Owner, Admin, and Member.
- A Restricted or child role is deferred.

### Member capabilities

Members may organize household content by default. An Owner or Admin may turn
off a Member's ability to create, edit, reorder, or delete rooms and tasks.

The initial UI will expose one **Can organize household** switch. The database
will retain separate room-management and task-management capabilities so the
product can separate them later without a schema redesign.

Owner and Admin capabilities cannot be disabled through Member overrides.
Server authorization, not UI visibility, is authoritative.

### Invitations

- Invitation links are freely forwardable bearer credentials.
- A link is single-use, revocable, and expires after seven days by default.
- The database stores only a hash of the invitation token.
- Acceptance requires an authenticated Tidyly account.
- The first eligible authenticated user to accept a link claims it.
- An Owner may create Admin or Member invitations.
- An Admin may create Member invitations only.
- Recipient-bound decline state is omitted. Dismissing a forwardable link does
  not invalidate it.
- Acceptance is transactional and fails if the invitation is claimed, expired,
  revoked, or the accepting user already has an active household.

### Task assignment

- A task may have zero or one assigned household membership initially.
- An unassigned task belongs to the household generally.
- Assignment communicates responsibility; it does not grant exclusive
  completion permission.
- Any member with completion permission may complete an assigned task.
- Members who can organize the household may assign or reassign tasks.
- Removing a member unassigns their active tasks while preserving historical
  completion and activity attribution.
- Multiple simultaneous assignees are deferred.

### Existing local data when joining

Tidyly will not merge existing local data into an invited household in the
initial release.

Before replacing the active local dataset, the app will:

1. Explain that the existing local household cannot yet be merged.
2. Offer a validated backup export.
3. Require explicit confirmation before continuing without a backup.
4. Archive the old local store for a recovery period rather than immediately
   destroying it.
5. Bootstrap and verify the shared household before making it active.

The archive will be eligible for manual deletion and automatic expiry under a
retention policy selected before implementation. Invitation acceptance and
local cleanup are separate operations so a failed bootstrap cannot destroy the
only usable local dataset.

## Domain model

All shared mutable records carry `household_id`, stable UUID identifiers,
server timestamps, actor attribution, a server-issued version, and an optional
deletion timestamp where soft deletion applies.

### users

- `id uuid primary key`, mapped to the backend auth user
- `display_name text`
- `avatar_url text null`
- `status user_status`
- `created_at timestamptz`
- `updated_at timestamptz`
- `last_seen_at timestamptz null`

Provider identities are separate from public household profiles. Email and
provider metadata are not exposed to other household members.

### households

- `id uuid primary key`
- `name text`
- `owner_user_id uuid references users`
- `week_starts_on smallint`
- `timezone_id text`
- `created_at timestamptz`
- `updated_at timestamptz`
- `deleted_at timestamptz null`
- `version bigint`

Exactly one active Owner membership must agree with `owner_user_id`.

### household_memberships

- `id uuid primary key`
- `household_id uuid references households`
- `user_id uuid references users`
- `role membership_role`
- `status membership_status`
- `can_manage_rooms boolean`
- `can_manage_tasks boolean`
- `can_complete_tasks boolean`
- `invited_by_user_id uuid null`
- `joined_at timestamptz`
- `left_at timestamptz null`
- `created_at timestamptz`
- `updated_at timestamptz`

There is at most one active membership per user globally and at most one active
membership per household/user pair.

### household_invitations

- `id uuid primary key`
- `household_id uuid references households`
- `invited_by_membership_id uuid references household_memberships`
- `intended_role membership_role`
- `token_hash text unique`
- `status invitation_status`
- `expires_at timestamptz`
- `accepted_by_user_id uuid null`
- `accepted_at timestamptz null`
- `revoked_at timestamptz null`
- `created_at timestamptz`

### rooms

- `id uuid primary key`
- `household_id uuid references households`
- `name text`
- `icon text`
- `color text`
- `sort_key text`
- creation/update attribution and timestamps
- `deleted_at timestamptz null`
- `version bigint`

### tasks

- `id uuid primary key`
- `household_id uuid references households`
- `room_id uuid null references rooms`
- `assigned_membership_id uuid null references household_memberships`
- `title text`
- `frequency_days integer`
- `priority task_priority`
- `estimated_minutes integer`
- `next_due_on date`
- `last_completed_at timestamptz null`
- `sort_key text`
- creation/update attribution and timestamps
- `deleted_at timestamptz null`
- `version bigint`

A null `room_id` represents a general household task. The existing sentinel
room UUID will not be carried into the server model.

### task_completions

- `id uuid primary key`
- `household_id uuid references households`
- `task_id uuid references tasks`
- `completed_by_membership_id uuid references household_memberships`
- `completed_at timestamptz`
- `effective_date date`
- `mutation_id uuid`
- `reversed_at timestamptz null`
- `reversed_by_membership_id uuid null`
- `created_at timestamptz`

Completion and reversal are idempotent transactional operations. Ordinary undo
does not physically delete completion history.

### activity_events

- `id uuid primary key`
- `household_id uuid references households`
- `actor_membership_id uuid null`
- `entity_type text`
- `entity_id uuid`
- `event_type text`
- `occurred_at timestamptz`
- `mutation_id uuid`
- `task_title_snapshot text null`
- `room_name_snapshot text null`
- `payload jsonb`

Activity events are immutable snapshots and remain intelligible after an entity
or member is removed.

## Synchronization rules

- Every client query and mutation is explicitly scoped to the active household.
- Realtime events trigger cache updates or reconciliation but are not assumed to
  be durable delivery.
- Clients perform a consistent initial bootstrap and retain a server cursor or
  sequence for incremental reconciliation.
- Offline mutations are written to a durable local outbox and applied
  optimistically to the cache.
- Every mutation has an idempotency identifier.
- The server returns the authoritative result, which replaces the optimistic
  projection.
- Task completion and reversal are append-oriented transactional operations.
- Scalar edits use optimistic concurrency against a server-issued version.
- Tombstones win over stale edits.
- Membership and ownership operations run only through privileged transactional
  functions.
- Device clocks do not determine conflict winners.

## Local and shared boundaries

Shared backend data includes household settings, members, invitations, rooms,
tasks, assignments, completions, and activity.

Device-local data includes notification authorization, scheduled notification
requests, device reminder overrides, selected UI state, appearance, widget
snapshots, cache metadata, sync cursors, pending mutations, diagnostics, and
temporary migration archives.

The widget continues to consume an App Group snapshot produced by the main iOS
app after cache changes.

## Migration principles

- Introduce repository protocols and authenticated household context before
  changing production persistence behavior.
- Keep SwiftData operational behind a local repository during the transition.
- Add household identifiers to cached shared models before enabling server
  synchronization.
- Preserve existing UUIDs where valid.
- Use resumable, idempotent migrations with explicit checkpoints.
- Verify server counts and referential integrity before marking migration
  complete.
- Never silently merge or destroy a dataset.
- Retain an export and rollback path through the migration window.
- Retire CloudKit writes only after server-authoritative behavior is proven.

## Delivery phases

1. Backend and authorization spike: schema, RLS tests, Sign in with Apple,
   invitation claim, realtime reconnect, and offline completion prototype.
2. Client decoupling: repositories, session/household context, cache boundaries,
   notification and widget coordinators.
3. Backend foundation: migrations, environments, transactional functions,
   audit events, backups, and monitoring.
4. Read-only shared household beta and cache bootstrap.
5. Incremental server-authoritative mutations and offline outbox.
6. Existing-data migration with backup/archive safeguards.
7. Cutover, observation period, and explicit legacy retirement.

## Consequences

### Positive

- Authorization rules can express real household roles and capability overrides.
- The authoritative data model is portable to Android and web.
- Relational constraints and transactions protect membership and ownership
  invariants.
- Backend observability and support tooling improve over shared CloudKit zones.
- SwiftData continues to provide responsive iOS reads and practical offline use.

### Costs and risks

- Tidyly must implement and test a deliberate offline outbox and reconciliation
  protocol.
- RLS mistakes can cause cross-household exposure and require exhaustive
  deny-by-default tests.
- Sign in with Apple recovery, revocation, deletion, and later identity linking
  require backend lifecycle handling.
- Existing devices may contain divergent SwiftData or CloudKit datasets.
- Realtime, activity retention, backups, email delivery, and storage introduce
  operational costs that must be monitored.

## Deferred decisions

- Recovery-archive retention duration.
- Additional identity providers and account-linking UI.
- Expanded recurrence rules beyond fixed day intervals.
- Multiple task assignees.
- Recipient-bound email invitations.
- Restricted or child accounts.
- Importing or merging local data into an already shared household.

