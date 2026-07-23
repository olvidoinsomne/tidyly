begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create type public.user_status as enum (
  'active',
  'deletion_pending',
  'deleted'
);

create type public.membership_role as enum (
  'owner',
  'admin',
  'member'
);

create type public.membership_status as enum (
  'active',
  'left',
  'removed'
);

create type public.invitation_status as enum (
  'pending',
  'accepted',
  'expired',
  'revoked'
);

create type public.task_priority as enum (
  'low',
  'medium',
  'high'
);

create table public.users (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null default 'Tidyly member'
    check (char_length(display_name) between 1 and 80),
  avatar_url text,
  status public.user_status not null default 'active',
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  last_seen_at timestamptz
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 100),
  owner_user_id uuid not null references public.users(id) on delete restrict,
  week_starts_on smallint not null default 1 check (week_starts_on between 0 and 6),
  timezone_id text not null default 'UTC' check (char_length(timezone_id) between 1 and 100),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  deleted_at timestamptz,
  version bigint not null default 1 check (version > 0)
);

create table public.household_memberships (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  user_id uuid not null references public.users(id) on delete restrict,
  role public.membership_role not null default 'member',
  status public.membership_status not null default 'active',
  can_manage_rooms boolean not null default true,
  can_manage_tasks boolean not null default true,
  can_complete_tasks boolean not null default true,
  invited_by_user_id uuid references public.users(id) on delete set null,
  joined_at timestamptz not null default statement_timestamp(),
  left_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  constraint household_memberships_status_dates_check check (
    (status = 'active' and left_at is null)
    or (status <> 'active' and left_at is not null)
  ),
  constraint household_memberships_household_id_id_key unique (household_id, id)
);

create unique index household_memberships_one_active_user
  on public.household_memberships(user_id)
  where status = 'active';

create unique index household_memberships_one_active_household_user
  on public.household_memberships(household_id, user_id)
  where status = 'active';

create unique index household_memberships_one_owner
  on public.household_memberships(household_id)
  where status = 'active' and role = 'owner';

create index household_memberships_active_household
  on public.household_memberships(household_id, user_id)
  where status = 'active';

create table public.household_invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  invited_by_membership_id uuid not null,
  intended_role public.membership_role not null default 'member'
    check (intended_role <> 'owner'),
  token_hash text not null unique,
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null,
  accepted_by_user_id uuid references public.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  constraint household_invitations_inviter_fk
    foreign key (household_id, invited_by_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint household_invitations_terminal_state_check check (
    (status = 'pending' and accepted_at is null and revoked_at is null)
    or (status = 'accepted' and accepted_at is not null and accepted_by_user_id is not null and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null and accepted_at is null)
    or (status = 'expired' and accepted_at is null and revoked_at is null)
  )
);

create index household_invitations_pending_lookup
  on public.household_invitations(token_hash, expires_at)
  where status = 'pending';

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  name text not null check (char_length(name) between 1 and 100),
  icon text not null default '🧹' check (char_length(icon) between 1 and 32),
  color text not null default '#3B82F6'
    check (color ~ '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$'),
  sort_order integer not null default 0,
  created_by_membership_id uuid,
  updated_by_membership_id uuid,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  deleted_at timestamptz,
  version bigint not null default 1 check (version > 0),
  constraint rooms_household_id_id_key unique (household_id, id),
  constraint rooms_created_by_fk
    foreign key (household_id, created_by_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint rooms_updated_by_fk
    foreign key (household_id, updated_by_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict
);

create index rooms_household_order
  on public.rooms(household_id, sort_order, id)
  where deleted_at is null;

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  room_id uuid,
  assigned_membership_id uuid,
  title text not null check (char_length(title) between 1 and 200),
  frequency_days integer not null default 7 check (frequency_days between 1 and 3650),
  priority public.task_priority not null default 'medium',
  estimated_minutes integer not null default 10 check (estimated_minutes between 1 and 1440),
  last_completed_at timestamptz,
  next_due_on date not null,
  sort_order integer not null default 0,
  created_by_membership_id uuid,
  updated_by_membership_id uuid,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  deleted_at timestamptz,
  version bigint not null default 1 check (version > 0),
  constraint tasks_room_fk
    foreign key (household_id, room_id)
    references public.rooms(household_id, id)
    on delete restrict,
  constraint tasks_assignee_fk
    foreign key (household_id, assigned_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint tasks_created_by_fk
    foreign key (household_id, created_by_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint tasks_updated_by_fk
    foreign key (household_id, updated_by_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint tasks_household_id_id_key unique (household_id, id)
);

create index tasks_household_due
  on public.tasks(household_id, next_due_on, sort_order, id)
  where deleted_at is null;

create index tasks_assignee
  on public.tasks(household_id, assigned_membership_id, next_due_on)
  where deleted_at is null and assigned_membership_id is not null;

create table public.task_completions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  task_id uuid not null,
  room_id uuid,
  completed_by_membership_id uuid not null,
  completed_at timestamptz not null,
  effective_date date not null,
  mutation_id uuid not null,
  previous_due_on date not null,
  previous_last_completed_at timestamptz,
  reversed_at timestamptz,
  reversed_by_membership_id uuid,
  created_at timestamptz not null default statement_timestamp(),
  constraint task_completions_task_fk
    foreign key (household_id, task_id)
    references public.tasks(household_id, id)
    on delete restrict,
  constraint task_completions_room_fk
    foreign key (household_id, room_id)
    references public.rooms(household_id, id)
    on delete restrict,
  constraint task_completions_actor_fk
    foreign key (household_id, completed_by_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint task_completions_reverser_fk
    foreign key (household_id, reversed_by_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint task_completions_reversal_check check (
    (reversed_at is null and reversed_by_membership_id is null)
    or (reversed_at is not null and reversed_by_membership_id is not null)
  ),
  constraint task_completions_household_mutation_key unique (household_id, mutation_id)
);

create index task_completions_task_history
  on public.task_completions(household_id, task_id, completed_at desc);

create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  actor_membership_id uuid,
  entity_type text not null check (char_length(entity_type) between 1 and 50),
  entity_id uuid not null,
  event_type text not null check (char_length(event_type) between 1 and 80),
  occurred_at timestamptz not null default statement_timestamp(),
  mutation_id uuid not null,
  task_title_snapshot text,
  room_name_snapshot text,
  payload jsonb not null default '{}'::jsonb,
  constraint activity_events_actor_fk
    foreign key (household_id, actor_membership_id)
    references public.household_memberships(household_id, id)
    on delete restrict,
  constraint activity_events_household_mutation_event_key
    unique (household_id, mutation_id, event_type)
);

create index activity_events_household_feed
  on public.activity_events(household_id, occurred_at desc, id);

create or replace function private.current_user_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select auth.uid()
$$;

create or replace function private.active_membership_id(target_household_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select membership.id
  from public.household_memberships as membership
  where membership.household_id = target_household_id
    and membership.user_id = (select auth.uid())
    and membership.status = 'active'
  limit 1
$$;

create or replace function private.is_active_household_member(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select private.active_membership_id(target_household_id)) is not null
$$;

create or replace function private.has_household_role(
  target_household_id uuid,
  allowed_roles public.membership_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_memberships as membership
    where membership.household_id = target_household_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and membership.role = any(allowed_roles)
  )
$$;

create or replace function private.can_manage_rooms(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_memberships as membership
    where membership.household_id = target_household_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and (
        membership.role in ('owner', 'admin')
        or membership.can_manage_rooms
      )
  )
$$;

create or replace function private.can_manage_tasks(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_memberships as membership
    where membership.household_id = target_household_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and (
        membership.role in ('owner', 'admin')
        or membership.can_manage_tasks
      )
  )
$$;

create or replace function private.can_complete_tasks(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_memberships as membership
    where membership.household_id = target_household_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and membership.can_complete_tasks
  )
$$;

create or replace function private.shares_active_household(other_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_memberships mine
    join public.household_memberships theirs
      on theirs.household_id = mine.household_id
    where mine.user_id = (select auth.uid())
      and mine.status = 'active'
      and theirs.user_id = other_user_id
      and theirs.status = 'active'
  )
$$;

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := statement_timestamp();
  return new;
end;
$$;

create or replace function private.touch_household()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.id <> old.id or new.owner_user_id <> old.owner_user_id then
    raise exception 'Household identity and ownership require a privileged operation';
  end if;
  new.created_at := old.created_at;
  new.updated_at := statement_timestamp();
  new.version := old.version + 1;
  return new;
end;
$$;

create or replace function private.touch_shared_record()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_membership_id uuid;
begin
  if tg_op = 'UPDATE' then
    if new.id <> old.id or new.household_id <> old.household_id then
      raise exception 'Shared record identity and household cannot be changed';
    end if;
    new.created_at := old.created_at;
    new.created_by_membership_id := old.created_by_membership_id;
    new.version := old.version + 1;
  end if;

  actor_membership_id := private.active_membership_id(new.household_id);
  if actor_membership_id is not null then
    if tg_op = 'INSERT' then
      new.created_by_membership_id := actor_membership_id;
    end if;
    new.updated_by_membership_id := actor_membership_id;
  end if;

  new.updated_at := statement_timestamp();
  return new;
end;
$$;

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      'Tidyly member'
    ),
    nullif(trim(new.raw_user_meta_data ->> 'avatar_url'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger auth_user_created
after insert on auth.users
for each row execute function private.handle_new_auth_user();

create trigger users_touch_updated_at
before update on public.users
for each row execute function private.touch_updated_at();

create trigger memberships_touch_updated_at
before update on public.household_memberships
for each row execute function private.touch_updated_at();

create trigger households_touch_version
before update on public.households
for each row execute function private.touch_household();

create trigger rooms_touch_version_and_actor
before insert or update on public.rooms
for each row execute function private.touch_shared_record();

create trigger tasks_touch_version_and_actor
before insert or update on public.tasks
for each row execute function private.touch_shared_record();

create or replace function public.create_household(
  p_household_name text,
  p_household_timezone_id text default 'UTC',
  p_week_starts_on integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  new_household_id uuid;
  new_membership_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if nullif(trim(p_household_name), '') is null then
    raise exception 'Household name is required' using errcode = '22023';
  end if;

  if p_week_starts_on < 0 or p_week_starts_on > 6 then
    raise exception 'Week start must be between 0 and 6' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.household_memberships
    where user_id = caller_id and status = 'active'
  ) then
    raise exception 'User already belongs to an active household' using errcode = '23505';
  end if;

  insert into public.households (name, owner_user_id, timezone_id, week_starts_on)
  values (
    trim(p_household_name),
    caller_id,
    p_household_timezone_id,
    p_week_starts_on::smallint
  )
  returning id into new_household_id;

  insert into public.household_memberships (
    household_id,
    user_id,
    role,
    can_manage_rooms,
    can_manage_tasks,
    can_complete_tasks
  )
  values (
    new_household_id,
    caller_id,
    'owner',
    true,
    true,
    true
  )
  returning id into new_membership_id;

  insert into public.activity_events (
    household_id,
    actor_membership_id,
    entity_type,
    entity_id,
    event_type,
    mutation_id,
    payload
  )
  values (
    new_household_id,
    new_membership_id,
    'household',
    new_household_id,
    'household_created',
    gen_random_uuid(),
    jsonb_build_object('name', trim(p_household_name))
  );

  return new_household_id;
end;
$$;

create or replace function public.create_household_invitation(
  p_intended_role public.membership_role default 'member',
  p_expires_in interval default interval '7 days'
)
returns table (
  invitation_id uuid,
  invitation_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_membership public.household_memberships;
  raw_token text;
begin
  select membership.*
  into caller_membership
  from public.household_memberships membership
  where membership.user_id = caller_id
    and membership.status = 'active'
  for update;

  if caller_membership.id is null or caller_membership.role not in ('owner', 'admin') then
    raise exception 'Owner or Admin membership required' using errcode = '42501';
  end if;

  if p_intended_role = 'owner' then
    raise exception 'Owner invitations are not allowed' using errcode = '22023';
  end if;

  if p_intended_role = 'admin' and caller_membership.role <> 'owner' then
    raise exception 'Only the Owner can invite an Admin' using errcode = '42501';
  end if;

  if p_expires_in <= interval '0 seconds' or p_expires_in > interval '30 days' then
    raise exception 'Invitation expiry must be between 1 second and 30 days' using errcode = '22023';
  end if;

  raw_token := encode(extensions.gen_random_bytes(32), 'hex');

  return query
  insert into public.household_invitations (
    household_id,
    invited_by_membership_id,
    intended_role,
    token_hash,
    expires_at
  )
  values (
    caller_membership.household_id,
    caller_membership.id,
    p_intended_role,
    encode(extensions.digest(raw_token, 'sha256'), 'hex'),
    statement_timestamp() + p_expires_in
  )
  returning
    household_invitations.id,
    raw_token,
    household_invitations.expires_at;
end;
$$;

create or replace function public.accept_household_invitation(p_invitation_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  claimed_invitation public.household_invitations;
  new_membership_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if exists (
    select 1
    from public.household_memberships
    where user_id = caller_id and status = 'active'
  ) then
    raise exception 'Leave the current household before accepting another invitation'
      using errcode = '23505';
  end if;

  select invitation.*
  into claimed_invitation
  from public.household_invitations invitation
  where invitation.token_hash = encode(
    extensions.digest(p_invitation_token, 'sha256'),
    'hex'
  )
  for update;

  if claimed_invitation.id is null then
    raise exception 'Invitation not found' using errcode = '22023';
  end if;

  if claimed_invitation.status <> 'pending' then
    raise exception 'Invitation is no longer available' using errcode = '22023';
  end if;

  if claimed_invitation.expires_at <= statement_timestamp() then
    update public.household_invitations
    set status = 'expired'
    where id = claimed_invitation.id;
    raise exception 'Invitation has expired' using errcode = '22023';
  end if;

  insert into public.household_memberships (
    household_id,
    user_id,
    role,
    can_manage_rooms,
    can_manage_tasks,
    can_complete_tasks,
    invited_by_user_id
  )
  select
    claimed_invitation.household_id,
    caller_id,
    claimed_invitation.intended_role,
    true,
    true,
    true,
    inviter.user_id
  from public.household_memberships inviter
  where inviter.id = claimed_invitation.invited_by_membership_id
  returning id into new_membership_id;

  update public.household_invitations
  set
    status = 'accepted',
    accepted_by_user_id = caller_id,
    accepted_at = statement_timestamp()
  where id = claimed_invitation.id;

  insert into public.activity_events (
    household_id,
    actor_membership_id,
    entity_type,
    entity_id,
    event_type,
    mutation_id,
    payload
  )
  values (
    claimed_invitation.household_id,
    new_membership_id,
    'membership',
    new_membership_id,
    'member_joined',
    gen_random_uuid(),
    jsonb_build_object('role', claimed_invitation.intended_role)
  );

  return claimed_invitation.household_id;
end;
$$;

create or replace function public.set_member_organization_permission(
  p_target_membership_id uuid,
  p_can_organize boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_membership public.household_memberships;
  target_membership public.household_memberships;
begin
  select membership.*
  into caller_membership
  from public.household_memberships membership
  where membership.user_id = auth.uid()
    and membership.status = 'active';

  select membership.*
  into target_membership
  from public.household_memberships membership
  where membership.id = p_target_membership_id
  for update;

  if caller_membership.id is null
     or caller_membership.household_id <> target_membership.household_id
     or caller_membership.role not in ('owner', 'admin') then
    raise exception 'Owner or Admin membership required' using errcode = '42501';
  end if;

  if target_membership.status <> 'active' or target_membership.role <> 'member' then
    raise exception 'Only an active Member can be restricted' using errcode = '22023';
  end if;

  update public.household_memberships
  set
    can_manage_rooms = p_can_organize,
    can_manage_tasks = p_can_organize
  where id = p_target_membership_id;
end;
$$;

create or replace function public.complete_task(
  p_target_task_id uuid,
  p_completed_at timestamptz,
  p_effective_date date,
  p_mutation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_task public.tasks;
  actor_membership_id uuid;
  existing_completion_id uuid;
  new_completion_id uuid;
  room_name text;
begin
  select completion.id
  into existing_completion_id
  from public.task_completions completion
  where completion.mutation_id = p_mutation_id
    and private.is_active_household_member(completion.household_id)
  limit 1;

  if existing_completion_id is not null then
    return existing_completion_id;
  end if;

  select task.*
  into target_task
  from public.tasks task
  where task.id = p_target_task_id
  for update;

  if target_task.id is null or target_task.deleted_at is not null then
    raise exception 'Task not found' using errcode = '22023';
  end if;

  actor_membership_id := private.active_membership_id(target_task.household_id);
  if actor_membership_id is null
     or not private.can_complete_tasks(target_task.household_id) then
    raise exception 'Task completion permission required' using errcode = '42501';
  end if;

  if target_task.room_id is null then
    room_name := 'Household';
  else
    select room.name
    into room_name
    from public.rooms room
    where room.id = target_task.room_id;
  end if;

  insert into public.task_completions (
    household_id,
    task_id,
    room_id,
    completed_by_membership_id,
    completed_at,
    effective_date,
    mutation_id,
    previous_due_on,
    previous_last_completed_at
  )
  values (
    target_task.household_id,
    target_task.id,
    target_task.room_id,
    actor_membership_id,
    p_completed_at,
    p_effective_date,
    p_mutation_id,
    target_task.next_due_on,
    target_task.last_completed_at
  )
  returning id into new_completion_id;

  update public.tasks
  set
    last_completed_at = p_completed_at,
    next_due_on = p_effective_date + target_task.frequency_days,
    updated_by_membership_id = actor_membership_id
  where id = target_task.id;

  insert into public.activity_events (
    household_id,
    actor_membership_id,
    entity_type,
    entity_id,
    event_type,
    occurred_at,
    mutation_id,
    task_title_snapshot,
    room_name_snapshot,
    payload
  )
  values (
    target_task.household_id,
    actor_membership_id,
    'task',
    target_task.id,
    'completed',
    p_completed_at,
    p_mutation_id,
    target_task.title,
    room_name,
    jsonb_build_object(
      'completion_id', new_completion_id,
      'previous_due_on', target_task.next_due_on,
      'resulting_due_on', p_effective_date + target_task.frequency_days,
      'previous_last_completed_at', target_task.last_completed_at,
      'resulting_last_completed_at', p_completed_at
    )
  );

  return new_completion_id;
end;
$$;

create or replace function public.reverse_task_completion(
  p_target_completion_id uuid,
  p_mutation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_completion public.task_completions;
  target_task public.tasks;
  actor_membership public.household_memberships;
  room_name text;
begin
  if exists (
    select 1
    from public.activity_events event
    where event.mutation_id = p_mutation_id
      and event.event_type = 'completion_reversed'
      and private.is_active_household_member(event.household_id)
  ) then
    return;
  end if;

  select completion.*
  into target_completion
  from public.task_completions completion
  where completion.id = p_target_completion_id
  for update;

  if target_completion.id is null or target_completion.reversed_at is not null then
    raise exception 'Active completion not found' using errcode = '22023';
  end if;

  select membership.*
  into actor_membership
  from public.household_memberships membership
  where membership.id = private.active_membership_id(target_completion.household_id);

  if actor_membership.id is null
     or not actor_membership.can_complete_tasks
     or (
       actor_membership.id <> target_completion.completed_by_membership_id
       and actor_membership.role not in ('owner', 'admin')
     ) then
    raise exception 'Completion reversal permission required' using errcode = '42501';
  end if;

  select task.*
  into target_task
  from public.tasks task
  where task.id = target_completion.task_id
  for update;

  if exists (
    select 1
    from public.task_completions later_completion
    where later_completion.task_id = target_completion.task_id
      and later_completion.reversed_at is null
      and later_completion.completed_at > target_completion.completed_at
  ) then
    raise exception 'Only the latest completion can be reversed' using errcode = '40001';
  end if;

  update public.task_completions
  set
    reversed_at = statement_timestamp(),
    reversed_by_membership_id = actor_membership.id
  where id = target_completion.id;

  update public.tasks
  set
    last_completed_at = target_completion.previous_last_completed_at,
    next_due_on = target_completion.previous_due_on,
    updated_by_membership_id = actor_membership.id
  where id = target_task.id;

  if target_task.room_id is null then
    room_name := 'Household';
  else
    select room.name into room_name
    from public.rooms room
    where room.id = target_task.room_id;
  end if;

  insert into public.activity_events (
    household_id,
    actor_membership_id,
    entity_type,
    entity_id,
    event_type,
    mutation_id,
    task_title_snapshot,
    room_name_snapshot,
    payload
  )
  values (
    target_task.household_id,
    actor_membership.id,
    'task',
    target_task.id,
    'completion_reversed',
    p_mutation_id,
    target_task.title,
    room_name,
    jsonb_build_object(
      'completion_id', target_completion.id,
      'resulting_due_on', target_completion.previous_due_on,
      'resulting_last_completed_at', target_completion.previous_last_completed_at
    )
  );
end;
$$;

alter table public.users enable row level security;
alter table public.households enable row level security;
alter table public.household_memberships enable row level security;
alter table public.household_invitations enable row level security;
alter table public.rooms enable row level security;
alter table public.tasks enable row level security;
alter table public.task_completions enable row level security;
alter table public.activity_events enable row level security;

create policy users_select_household_profiles
on public.users
for select
to authenticated
using (
  id = (select auth.uid())
  or (select private.shares_active_household(id))
);

create policy users_update_self
on public.users
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()) and status = 'active');

create policy households_select_active_member
on public.households
for select
to authenticated
using ((select private.is_active_household_member(id)));

create policy memberships_select_active_household
on public.household_memberships
for select
to authenticated
using ((select private.is_active_household_member(household_id)));

create policy invitations_select_household_managers
on public.household_invitations
for select
to authenticated
using (
  (select private.has_household_role(
    household_id,
    array['owner', 'admin']::public.membership_role[]
  ))
);

create policy rooms_select_active_household
on public.rooms
for select
to authenticated
using ((select private.is_active_household_member(household_id)));

create policy rooms_insert_household_organizer
on public.rooms
for insert
to authenticated
with check ((select private.can_manage_rooms(household_id)));

create policy rooms_update_household_organizer
on public.rooms
for update
to authenticated
using ((select private.can_manage_rooms(household_id)))
with check ((select private.can_manage_rooms(household_id)));

create policy tasks_select_active_household
on public.tasks
for select
to authenticated
using ((select private.is_active_household_member(household_id)));

create policy tasks_insert_household_organizer
on public.tasks
for insert
to authenticated
with check ((select private.can_manage_tasks(household_id)));

create policy tasks_update_household_organizer
on public.tasks
for update
to authenticated
using ((select private.can_manage_tasks(household_id)))
with check ((select private.can_manage_tasks(household_id)));

create policy completions_select_active_household
on public.task_completions
for select
to authenticated
using ((select private.is_active_household_member(household_id)));

create policy activity_select_active_household
on public.activity_events
for select
to authenticated
using ((select private.is_active_household_member(household_id)));

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

grant select on public.users to authenticated;
grant update (display_name, avatar_url, last_seen_at) on public.users to authenticated;

grant select on public.households to authenticated;
grant select on public.household_memberships to authenticated;
grant select on public.household_invitations to authenticated;

grant select on public.rooms to authenticated;
grant insert (
  id,
  household_id,
  name,
  icon,
  color,
  sort_order,
  deleted_at
) on public.rooms to authenticated;
grant update (
  name,
  icon,
  color,
  sort_order,
  deleted_at
) on public.rooms to authenticated;

grant select on public.tasks to authenticated;
grant insert (
  id,
  household_id,
  room_id,
  assigned_membership_id,
  title,
  frequency_days,
  priority,
  estimated_minutes,
  next_due_on,
  sort_order,
  deleted_at
) on public.tasks to authenticated;
grant update (
  room_id,
  assigned_membership_id,
  title,
  frequency_days,
  priority,
  estimated_minutes,
  next_due_on,
  sort_order,
  deleted_at
) on public.tasks to authenticated;

grant select on public.task_completions to authenticated;
grant select on public.activity_events to authenticated;

grant execute on function public.create_household(text, text, integer) to authenticated;
grant execute on function public.create_household_invitation(public.membership_role, interval) to authenticated;
grant execute on function public.accept_household_invitation(text) to authenticated;
grant execute on function public.set_member_organization_permission(uuid, boolean) to authenticated;
grant execute on function public.complete_task(uuid, timestamptz, date, uuid) to authenticated;
grant execute on function public.reverse_task_completion(uuid, uuid) to authenticated;

alter table public.users replica identity full;
alter table public.households replica identity full;
alter table public.household_memberships replica identity full;
alter table public.rooms replica identity full;
alter table public.tasks replica identity full;
alter table public.task_completions replica identity full;
alter table public.activity_events replica identity full;

alter publication supabase_realtime add table public.users;
alter publication supabase_realtime add table public.households;
alter publication supabase_realtime add table public.household_memberships;
alter publication supabase_realtime add table public.rooms;
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.task_completions;
alter publication supabase_realtime add table public.activity_events;

commit;
