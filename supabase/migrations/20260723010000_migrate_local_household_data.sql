begin;

create or replace function public.migrate_local_household_data(
  p_rooms jsonb,
  p_tasks jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  target_household_id uuid;
  room_count integer;
  task_count integer;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select membership.household_id
  into target_household_id
  from public.household_memberships membership
  where membership.user_id = caller_id
    and membership.status = 'active'
    and membership.can_manage_rooms
    and membership.can_manage_tasks;

  if target_household_id is null then
    raise exception 'Active household organizer membership required' using errcode = '42501';
  end if;

  if jsonb_typeof(coalesce(p_rooms, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_tasks, '[]'::jsonb)) <> 'array' then
    raise exception 'Rooms and tasks must be JSON arrays' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_household_id::text, 0));

  if exists (
    select 1 from public.rooms
    where household_id = target_household_id and deleted_at is null
  ) or exists (
    select 1 from public.tasks
    where household_id = target_household_id and deleted_at is null
  ) then
    raise exception 'Supabase household must be empty before migration' using errcode = '23505';
  end if;

  insert into public.rooms (
    id, household_id, name, icon, color, sort_order, created_at, updated_at
  )
  select
    (room ->> 'id')::uuid,
    target_household_id,
    room ->> 'name',
    room ->> 'icon',
    room ->> 'color',
    coalesce((room ->> 'sort_order')::integer, 0),
    coalesce((room ->> 'created_at')::timestamptz, statement_timestamp()),
    coalesce((room ->> 'updated_at')::timestamptz, statement_timestamp())
  from jsonb_array_elements(coalesce(p_rooms, '[]'::jsonb)) room;

  insert into public.tasks (
    id, household_id, room_id, assigned_membership_id, title,
    frequency_days, priority, estimated_minutes, last_completed_at,
    next_due_on, sort_order, created_at, updated_at
  )
  select
    (task ->> 'id')::uuid,
    target_household_id,
    nullif(task ->> 'room_id', '')::uuid,
    null,
    task ->> 'title',
    coalesce((task ->> 'frequency_days')::integer, 7),
    coalesce(task ->> 'priority', 'medium')::public.task_priority,
    coalesce((task ->> 'estimated_minutes')::integer, 10),
    nullif(task ->> 'last_completed_at', '')::timestamptz,
    (task ->> 'next_due_on')::date,
    coalesce((task ->> 'sort_order')::integer, 0),
    coalesce((task ->> 'created_at')::timestamptz, statement_timestamp()),
    coalesce((task ->> 'updated_at')::timestamptz, statement_timestamp())
  from jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) task;

  select count(*)::integer into room_count
  from public.rooms where household_id = target_household_id and deleted_at is null;
  select count(*)::integer into task_count
  from public.tasks where household_id = target_household_id and deleted_at is null;

  insert into public.activity_events (
    household_id, actor_membership_id, entity_type, entity_id,
    event_type, mutation_id, payload
  )
  values (
    target_household_id,
    private.active_membership_id(target_household_id),
    'household',
    target_household_id,
    'local_data_migrated',
    gen_random_uuid(),
    jsonb_build_object('room_count', room_count, 'task_count', task_count)
  );

  return jsonb_build_object('room_count', room_count, 'task_count', task_count);
end;
$$;

revoke all on function public.migrate_local_household_data(jsonb, jsonb)
from public, anon, authenticated;
grant execute on function public.migrate_local_household_data(jsonb, jsonb)
to authenticated;

commit;
