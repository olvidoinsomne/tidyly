create extension if not exists pgtap with schema extensions;

begin;

select plan(17);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'owner@tidyly.test',
    '{"provider":"apple","providers":["apple"]}',
    '{"full_name":"Household Owner"}',
    statement_timestamp(),
    statement_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'member@tidyly.test',
    '{"provider":"apple","providers":["apple"]}',
    '{"full_name":"Household Member"}',
    statement_timestamp(),
    statement_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'outsider@tidyly.test',
    '{"provider":"apple","providers":["apple"]}',
    '{"full_name":"Other User"}',
    statement_timestamp(),
    statement_timestamp()
  );

create temporary table workflow_context (
  household_id uuid,
  invitation_id uuid,
  invitation_token text,
  revoked_invitation_id uuid,
  revoked_invitation_token text,
  expired_invitation_id uuid,
  expired_invitation_token text,
  member_membership_id uuid,
  room_id uuid,
  task_id uuid,
  completion_id uuid,
  completion_mutation_id uuid,
  reversal_mutation_id uuid
) on commit drop;

insert into workflow_context (
  room_id,
  task_id,
  completion_mutation_id,
  reversal_mutation_id
)
values (
  '20000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000002'
);

grant all on workflow_context to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

update workflow_context
set household_id = public.create_household(
  'Test Home',
  'America/New_York',
  1
);

select is(
  (
    select count(*)::bigint
    from public.household_memberships
    where household_id = (select household_id from workflow_context)
      and role = 'owner'
      and status = 'active'
  ),
  1::bigint,
  'household creation creates exactly one active Owner'
);

with invitation as (
  select *
  from public.create_household_invitation(
    'member'::public.membership_role,
    interval '7 days'
  )
)
update workflow_context context
set
  invitation_id = invitation.invitation_id,
  invitation_token = invitation.invitation_token
from invitation;

with invitation as (
  select *
  from public.create_household_invitation(
    'member'::public.membership_role,
    interval '7 days'
  )
)
update workflow_context context
set
  revoked_invitation_id = invitation.invitation_id,
  revoked_invitation_token = invitation.invitation_token
from invitation;

with invitation as (
  select *
  from public.create_household_invitation(
    'member'::public.membership_role,
    interval '7 days'
  )
)
update workflow_context context
set
  expired_invitation_id = invitation.invitation_id,
  expired_invitation_token = invitation.invitation_token
from invitation;

update public.household_invitations
set status = 'revoked', revoked_at = statement_timestamp()
where id = (select revoked_invitation_id from workflow_context);

update public.household_invitations
set expires_at = statement_timestamp() - interval '1 second'
where id = (select expired_invitation_id from workflow_context);

select ok(
  (select invitation_token is not null from workflow_context),
  'owner receives the raw one-time invitation token'
);

select is(
  (
    select length(token_hash)
    from public.household_invitations
    where id = (select invitation_id from workflow_context)
  ),
  64,
  'only a SHA-256 invitation token hash is stored'
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000002',
  true
);

select is(
  public.accept_household_invitation(
    (select invitation_token from workflow_context)
  ),
  (select household_id from workflow_context),
  'member accepts the forwardable invitation'
);

update workflow_context context
set member_membership_id = membership.id
from public.household_memberships membership
where membership.household_id = context.household_id
  and membership.user_id = '10000000-0000-0000-0000-000000000002'
  and membership.status = 'active';

select is(
  (
    select count(*)::bigint
    from public.users
    where id in (
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002'
    )
  ),
  2::bigint,
  'household members can see each other'
);

insert into public.rooms (
  id,
  household_id,
  name,
  icon,
  color,
  sort_order
)
select
  room_id,
  household_id,
  'Kitchen',
  '🍽️',
  '#3B82F6',
  0
from workflow_context;

insert into public.tasks (
  id,
  household_id,
  room_id,
  assigned_membership_id,
  title,
  frequency_days,
  priority,
  estimated_minutes,
  next_due_on,
  sort_order
)
select
  task_id,
  household_id,
  room_id,
  member_membership_id,
  'Wipe counters',
  7,
  'medium',
  10,
  date '2026-07-23',
  0
from workflow_context;

select is(
  (
    select assigned_membership_id
    from public.tasks
    where id = (select task_id from workflow_context)
  ),
  (select member_membership_id from workflow_context),
  'an organizing Member can create and assign a task'
);

update workflow_context
set completion_id = public.complete_task(
  task_id,
  timestamptz '2026-07-23 14:00:00+00',
  date '2026-07-23',
  completion_mutation_id
);

select is(
  (
    select next_due_on
    from public.tasks
    where id = (select task_id from workflow_context)
  ),
  date '2026-07-30',
  'task completion advances the authoritative due date'
);

select is(
  public.complete_task(
    (select task_id from workflow_context),
    timestamptz '2026-07-23 14:00:00+00',
    date '2026-07-23',
    (select completion_mutation_id from workflow_context)
  ),
  (select completion_id from workflow_context),
  'repeating a completion mutation is idempotent'
);

select lives_ok(
  format(
    'select public.reverse_task_completion(%L::uuid, %L::uuid)',
    (select completion_id from workflow_context),
    (select reversal_mutation_id from workflow_context)
  ),
  'the completing Member can reverse their latest completion'
);

select is(
  (
    select next_due_on
    from public.tasks
    where id = (select task_id from workflow_context)
  ),
  date '2026-07-23',
  'completion reversal restores the previous due date'
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select lives_ok(
  format(
    'select public.set_member_organization_permission(%L::uuid, false)',
    (select member_membership_id from workflow_context)
  ),
  'Owner can disable the Member organizer capability'
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000002',
  true
);

select throws_ok(
  format(
    $sql$
      insert into public.tasks (
        household_id,
        title,
        frequency_days,
        priority,
        estimated_minutes,
        next_due_on
      )
      values (%L::uuid, 'Blocked task', 7, 'medium', 10, date '2026-07-24')
    $sql$,
    (select household_id from workflow_context)
  ),
  '42501',
  'new row violates row-level security policy for table "tasks"',
  'restricted Member cannot create tasks'
);

select throws_ok(
  $$ select public.accept_household_invitation('malformed-token') $$,
  '22023',
  'Invitation not found',
  'a malformed invitation token is rejected without membership changes'
);

select throws_ok(
  $$ select public.accept_household_invitation((select revoked_invitation_token from workflow_context)) $$,
  '22023',
  'Invitation is no longer available',
  'a revoked invitation cannot be accepted'
);

select throws_ok(
  $$ select public.accept_household_invitation((select expired_invitation_token from workflow_context)) $$,
  '22023',
  'Invitation has expired',
  'an expired invitation cannot be accepted'
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);

select lives_ok(
  $$select public.create_household('Other Home', 'UTC', 1)$$,
  'an unrelated user can create a separate household'
);

select is(
  (
    select count(*)::bigint
    from public.rooms
    where id = '20000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'RLS hides another household room from an outsider'
);

select * from finish();

rollback;
