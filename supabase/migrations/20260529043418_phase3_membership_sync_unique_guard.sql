-- Keep member_directory -> memberships sync compatible with the person-era
-- active membership uniqueness rules. A person may belong to several groups,
-- but the same person/group (or same unassigned department row) can only have
-- one active membership. Legacy alias rows can be reactivated during regrouping,
-- so the sync trigger must end the older conflicting active row before upserting
-- the row for NEW.id.

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
  if new.church_id is null then
    return new;
  end if;

  v_person_id := public.phase2_upsert_person(
    new.church_id,
    new.person_id,
    new.profile_id,
    new.id,
    new.full_name,
    new.phone
  );
  v_phone := public.phase2_normalize_phone(new.phone);

  insert into public.person_identifiers (
    person_id,
    kind,
    value,
    source_table,
    source_id,
    is_primary
  )
  values (v_person_id, 'legacy_directory', new.id::text, 'member_directory', new.id, false)
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
    values (v_person_id, 'phone', v_phone, 'member_directory', new.id, false)
    on conflict do nothing;
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
    new.profile_id,
    new.id,
    new.full_name,
    new.phone,
    new.avatar_url,
    new.family_name
  )
  on conflict (member_directory_id) do update set
    person_id = excluded.person_id,
    profile_id = excluded.profile_id,
    full_name = excluded.full_name,
    phone = excluded.phone,
    avatar_url = excluded.avatar_url,
    family_name = excluded.family_name,
    updated_at = now();

  select id into v_group_id
  from public.groups
  where church_id = new.church_id
    and department_id = new.department_id
    and name = new.group_name
  limit 1;

  if coalesce(new.is_active, true) then
    update public.memberships m
    set status = 'ended',
        ends_at = coalesce(m.ends_at, now()),
        updated_at = now()
    where m.church_id = new.church_id
      and m.department_id = new.department_id
      and m.person_id = v_person_id
      and m.status = 'active'
      and (
        (m.group_id is null and v_group_id is null)
        or m.group_id = v_group_id
      )
      and m.legacy_member_directory_id is distinct from new.id;
  end if;

  if v_group_id is null
     or not exists (
       select 1
       from public.group_members gm
       where gm.member_directory_id = new.id
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
      new.church_id,
      new.department_id,
      v_group_id,
      case when new.role_in_group = 'leader' then 'leader' else 'member' end,
      case when coalesce(new.is_active, true) then 'active' else 'inactive' end,
      case
        when coalesce(new.is_active, true) then coalesce(new.joined_at, new.created_at, now())
        else least(
          coalesce(new.joined_at, new.created_at, now()),
          coalesce(new.left_at, now())
        )
      end,
      case when coalesce(new.is_active, true) then null else coalesce(new.left_at, now()) end,
      new.id
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
      starts_at = excluded.starts_at,
      ends_at = excluded.ends_at,
      updated_at = now();
  else
    update public.memberships
    set status = 'ended',
        ends_at = coalesce(ends_at, now()),
        updated_at = now()
    where legacy_member_directory_id = new.id
      and legacy_group_member_id is null
      and status = 'active';
  end if;

  return new;
end;
$$;

create or replace function public.phase2_sync_group_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group record;
  v_directory record;
  v_person_id uuid;
  v_profile_person_id uuid;
  v_profile_full_name text;
  v_profile_phone text;
  v_display_name text;
  v_legacy_member_directory_id uuid;
  v_status text;
  v_ends_at timestamptz;
begin
  select id, church_id, department_id
  into v_group
  from public.groups
  where id = new.group_id;

  if v_group.id is null or v_group.church_id is null then
    return new;
  end if;

  if new.member_directory_id is not null then
    select *
    into v_directory
    from public.member_directory
    where id = new.member_directory_id;
  end if;

  if new.profile_id is not null then
    select person_id, full_name, phone
    into v_profile_person_id, v_profile_full_name, v_profile_phone
    from public.profiles
    where id = new.profile_id;
  end if;

  v_display_name := coalesce(
    v_directory.full_name,
    v_profile_full_name,
    '[legacy missing member_directory]'
  );
  v_legacy_member_directory_id := v_directory.id;
  v_status := case
    when coalesce(new.is_active, true)
      and (new.member_directory_id is null or v_directory.id is not null) then 'active'
    when new.member_directory_id is not null and v_directory.id is null then 'ended'
    else 'inactive'
  end;
  v_ends_at := case
    when v_status = 'active' then null
    else now()
  end;

  v_person_id := public.phase2_upsert_person(
    v_group.church_id,
    coalesce(v_directory.person_id, v_profile_person_id),
    new.profile_id,
    new.member_directory_id,
    v_display_name,
    coalesce(v_directory.phone, v_profile_phone)
  );

  if v_status = 'active' then
    update public.memberships m
    set status = 'ended',
        ends_at = coalesce(m.ends_at, now()),
        updated_at = now()
    where m.church_id = v_group.church_id
      and m.department_id = v_group.department_id
      and m.person_id = v_person_id
      and m.group_id = new.group_id
      and m.status = 'active'
      and m.legacy_group_member_id is distinct from new.id;
  end if;

  insert into public.memberships (
    person_id,
    church_id,
    department_id,
    group_id,
    role,
    status,
    starts_at,
    ends_at,
    legacy_group_member_id,
    legacy_member_directory_id
  )
  values (
    v_person_id,
    v_group.church_id,
    v_group.department_id,
    new.group_id,
    case when new.role_in_group = 'leader' then 'leader' else 'member' end,
    v_status,
    coalesce(new.joined_at, now()),
    v_ends_at,
    new.id,
    v_legacy_member_directory_id
  )
  on conflict (legacy_group_member_id) do update set
    person_id = excluded.person_id,
    church_id = excluded.church_id,
    department_id = excluded.department_id,
    group_id = excluded.group_id,
    role = excluded.role,
    status = excluded.status,
    ends_at = excluded.ends_at,
    legacy_member_directory_id = excluded.legacy_member_directory_id,
    updated_at = now();

  return new;
end;
$$;
