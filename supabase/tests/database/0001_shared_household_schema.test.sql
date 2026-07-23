create extension if not exists pgtap with schema extensions;

begin;

select plan(34);

select has_schema('private', 'private helper schema exists');

select has_table('public', 'users', 'users table exists');
select has_table('public', 'households', 'households table exists');
select has_table('public', 'household_memberships', 'memberships table exists');
select has_table('public', 'household_invitations', 'invitations table exists');
select has_table('public', 'rooms', 'rooms table exists');
select has_table('public', 'tasks', 'tasks table exists');
select has_table('public', 'task_completions', 'completions table exists');
select has_table('public', 'activity_events', 'activity table exists');

select col_is_pk('public', 'users', 'id', 'users use UUID identity');
select col_is_pk('public', 'households', 'id', 'households use UUID identity');
select col_is_pk('public', 'rooms', 'id', 'rooms preserve UUID identity');
select col_is_pk('public', 'tasks', 'id', 'tasks preserve UUID identity');

select has_column('public', 'rooms', 'sort_order', 'CloudKit room ordering is preserved');
select has_column('public', 'tasks', 'frequency_days', 'CloudKit task recurrence is preserved');
select has_column('public', 'tasks', 'estimated_minutes', 'CloudKit task estimate is preserved');
select has_column('public', 'tasks', 'last_completed_at', 'CloudKit lastDoneAt projection is preserved');
select has_column('public', 'tasks', 'next_due_on', 'CloudKit nextDueAt projection is preserved');
select has_column('public', 'tasks', 'assigned_membership_id', 'tasks support member assignment');
select has_column('public', 'tasks', 'deleted_at', 'tasks use soft deletion');
select has_column('public', 'tasks', 'version', 'tasks support optimistic concurrency');

select has_function(
  'public',
  'create_household',
  array['text', 'text', 'integer'],
  'household creation RPC exists'
);
select has_function(
  'public',
  'create_household_invitation',
  array['membership_role', 'interval'],
  'invitation creation RPC exists'
);
select has_function(
  'public',
  'accept_household_invitation',
  array['text'],
  'invitation acceptance RPC exists'
);
select has_function(
  'public',
  'complete_task',
  array['uuid', 'timestamp with time zone', 'date', 'uuid'],
  'idempotent task completion RPC exists'
);
select has_function(
  'public',
  'reverse_task_completion',
  array['uuid', 'uuid'],
  'completion reversal RPC exists'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.users'::regclass),
  'users enforce RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.households'::regclass),
  'households enforce RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.household_memberships'::regclass),
  'memberships enforce RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.household_invitations'::regclass),
  'invitations enforce RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.rooms'::regclass),
  'rooms enforce RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.tasks'::regclass),
  'tasks enforce RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.task_completions'::regclass),
  'completions enforce RLS'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.activity_events'::regclass),
  'activity events enforce RLS'
);

select * from finish();

rollback;
