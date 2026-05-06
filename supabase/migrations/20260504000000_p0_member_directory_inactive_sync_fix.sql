-- Ensure member_directory deactivation ends/inactivates every Phase 2 active membership path,
-- including rows linked through legacy_group_member_id.

set check_function_bodies = off;

create or replace function public.phase2_sync_member_directory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_person_id uuid;
  v_phone text;
  v_group_id uuid;
begin
  if NEW.church_id is null then
    return NEW;
  end if;

  v_person_id := public.phase2_upsert_person(
    NEW.church_id,
    NEW.person_id,
    NEW.profile_id,
    NEW.id,
    NEW.full_name,
    NEW.phone
  );
  v_phone := public.phase2_normalize_phone(NEW.phone);

  insert into public.person_identifiers (
    person_id,
    kind,
    value,
    source_table,
    source_id,
    is_primary
  )
  values (v_person_id, 'legacy_directory', NEW.id::text, 'member_directory', NEW.id, false)
  on conflict do nothing;

  if v_phone is not null then
    insert into public.person_identifiers (
      person_id,
      kind,
      value,
      source_table,
      source_id,
      is_primary
    )
    values (v_person_id, 'phone', v_phone, 'member_directory', NEW.id, false)
    on conflict (kind, source_table, source_id)
      where source_table is not null and source_id is not null
    do update set
      person_id = excluded.person_id,
      value = excluded.value,
      is_primary = excluded.is_primary;
  else
    delete from public.person_identifiers
    where kind = 'phone'
      and source_table = 'member_directory'
      and source_id = NEW.id;
  end if;

  insert into public.member_profiles (
    person_id,
    profile_id,
    member_directory_id,
    full_name,
    phone,
    avatar_url,
    family_name
  )
  values (
    v_person_id,
    NEW.profile_id,
    NEW.id,
    NEW.full_name,
    NEW.phone,
    NEW.avatar_url,
    NEW.family_name
  )
  on conflict (member_directory_id) do update set
    person_id = excluded.person_id,
    profile_id = excluded.profile_id,
    full_name = excluded.full_name,
    phone = excluded.phone,
    avatar_url = excluded.avatar_url,
    family_name = excluded.family_name,
    updated_at = now();

  if not coalesce(NEW.is_active, true) then
    update public.group_members
    set is_active = false
    where member_directory_id = NEW.id
      and is_active = true;

    update public.memberships
    set status = 'inactive',
        ends_at = coalesce(ends_at, NEW.left_at, now()),
        updated_at = now()
    where legacy_member_directory_id = NEW.id
      and status = 'active';

    return NEW;
  end if;

  select id into v_group_id
  from public.groups
  where church_id = NEW.church_id
    and department_id = NEW.department_id
    and name = NEW.group_name
    and is_active = true
  limit 1;

  if v_group_id is not null
    and not exists (
      select 1
      from public.group_members gm
      where gm.member_directory_id = NEW.id
        and gm.is_active = true
    )
  then
    insert into public.memberships (
      person_id,
      church_id,
      department_id,
      group_id,
      role,
      status,
      starts_at,
      ends_at,
      legacy_member_directory_id
    )
    values (
      v_person_id,
      NEW.church_id,
      NEW.department_id,
      v_group_id,
      case when NEW.role_in_group = 'leader' then 'leader' else 'member' end,
      'active',
      coalesce(NEW.joined_at, NEW.created_at, now()),
      null,
      NEW.id
    )
    on conflict (legacy_member_directory_id)
      where legacy_group_member_id is null and legacy_member_directory_id is not null
    do update set
      person_id = excluded.person_id,
      church_id = excluded.church_id,
      department_id = excluded.department_id,
      group_id = excluded.group_id,
      role = excluded.role,
      status = excluded.status,
      ends_at = excluded.ends_at,
      updated_at = now();
  else
    update public.memberships
    set status = 'ended',
        ends_at = coalesce(ends_at, now()),
        updated_at = now()
    where legacy_member_directory_id = NEW.id
      and legacy_group_member_id is null
      and status = 'active';
  end if;

  return NEW;
end;
$$;
