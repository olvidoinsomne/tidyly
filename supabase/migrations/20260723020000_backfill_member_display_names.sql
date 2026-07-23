begin;

update public.users profile
set display_name = coalesce(
  nullif(trim(auth_user.raw_user_meta_data ->> 'full_name'), ''),
  nullif(trim(auth_user.raw_user_meta_data ->> 'name'), ''),
  nullif(trim(concat_ws(
    ' ',
    auth_user.raw_user_meta_data ->> 'given_name',
    auth_user.raw_user_meta_data ->> 'family_name'
  )), ''),
  profile.display_name
)
from auth.users auth_user
where auth_user.id = profile.id
  and profile.display_name = 'Tidyly member';

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
      nullif(trim(concat_ws(
        ' ',
        new.raw_user_meta_data ->> 'given_name',
        new.raw_user_meta_data ->> 'family_name'
      )), ''),
      'Tidyly member'
    ),
    nullif(trim(new.raw_user_meta_data ->> 'avatar_url'), '')
  )
  on conflict (id) do update
  set display_name = case
    when public.users.display_name = 'Tidyly member'
      then excluded.display_name
    else public.users.display_name
  end;
  return new;
end;
$$;

commit;
