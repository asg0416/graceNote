-- Phase 3 regrouping save sync fix:
-- Keep legacy group_members in sync even for directory-only people
-- (member_directory rows without a linked profiles row).

set check_function_bodies = off;

create or replace function public.sync_directory_to_group_members()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
  v_group_member_id uuid;
begin
  select id
  into v_group_id
  from public.groups
  where church_id = NEW.church_id
    and department_id = NEW.department_id
    and name = NEW.group_name
    and is_active = true
  limit 1;

  if not coalesce(NEW.is_active, true) or v_group_id is null then
    update public.group_members
    set is_active = false
    where member_directory_id = NEW.id
      and is_active = true;

    return NEW;
  end if;

  insert into public.group_members (
    group_id,
    profile_id,
    member_directory_id,
    role_in_group,
    is_active,
    joined_at
  )
  values (
    v_group_id,
    NEW.profile_id,
    NEW.id,
    case when NEW.role_in_group = 'leader' then 'leader' else 'member' end,
    true,
    coalesce(NEW.joined_at, now())
  )
  on conflict (group_id, member_directory_id) do update
  set profile_id = excluded.profile_id,
      role_in_group = excluded.role_in_group,
      is_active = true
  returning id into v_group_member_id;

  update public.group_members
  set is_active = false
  where member_directory_id = NEW.id
    and id <> v_group_member_id
    and is_active = true;

  return NEW;
end;
$$;

-- Repair active directory rows that were moved while profile_id was null.
-- Mentioning group_name in the UPDATE fires the existing sync triggers.
update public.member_directory
set group_name = group_name
where is_active is not false
  and nullif(btrim(group_name), '') is not null;
