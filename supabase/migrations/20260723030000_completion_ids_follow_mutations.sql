begin;

create or replace function private.use_mutation_as_completion_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.id := new.mutation_id;
  return new;
end;
$$;

create trigger task_completions_use_mutation_id
before insert on public.task_completions
for each row execute function private.use_mutation_as_completion_id();

commit;
