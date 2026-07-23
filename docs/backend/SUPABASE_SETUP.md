# Supabase backend setup

The version-controlled Supabase backend lives in `supabase/`. Its initial
migration implements the shared-household architecture accepted in
`docs/architecture/ADR-001-shared-household-backend.md`.

## CloudKit compatibility

The server schema preserves the existing CloudKit identifiers and fields:

| Existing record | PostgreSQL target |
| --- | --- |
| `TidylyHousehold.householdID` | `households.id` |
| Household `name` | `households.name` |
| Room UUID and fields | `rooms.id`, `name`, `icon`, `color`, `sort_order`, timestamps |
| Task UUID and fields | `tasks.id`, `title`, `frequency_days`, `priority`, `estimated_minutes`, `last_completed_at`, `next_due_on`, `sort_order`, timestamps |
| General household task sentinel | `tasks.room_id is null` |
| SwiftData completion | `task_completions` |
| SwiftData activity snapshot | `activity_events` |

The migration adds authoritative users, household memberships, invitations,
member capability overrides, task assignments, server versions, soft deletion,
idempotent mutations, RLS, and realtime publication.

## Local prerequisites

- Docker Desktop or another Docker-compatible runtime
- Node.js/npm

The Supabase CLI is invoked through `npx`, so a global installation is not
required.

## Local workflow

From the repository root:

```sh
npx supabase start
npx supabase db reset --local
npx supabase test db
```

`db reset --local` is destructive only to the local Supabase development
database. Never use `db reset --linked` against production.

The generated local API URL and publishable/anonymous key are printed by
`supabase start`. Do not commit hosted project secrets, service-role keys, or
Apple private keys.

## Sign in with Apple

The local provider is declared but disabled in `supabase/config.toml`. Configure
the hosted Supabase project's Apple provider before client integration.
Production credentials should be supplied through protected environment
variables or the hosted dashboard, never checked into this repository.

Native Apple login should exchange its Apple identity token with Supabase Auth.
The `auth.users` trigger creates the corresponding public Tidyly profile.

## Hosted project deployment

After creating separate staging and production Supabase projects:

```sh
npx supabase login
npx supabase link --project-ref <staging-project-ref>
npx supabase migration list
npx supabase db push
```

Review the target project before every linked command. Apply and test migrations
in staging before production. Linking state under `supabase/.temp/` remains
ignored by the generated Supabase `.gitignore`.

## Client boundary

This setup does not yet replace `DatabaseService` or enable Supabase in the iOS
app. SwiftData and CloudKit behavior remain unchanged until the client
repository/cache migration is implemented behind feature flags.
