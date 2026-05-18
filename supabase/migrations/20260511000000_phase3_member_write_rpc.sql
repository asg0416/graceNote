-- Phase 3 member write RPC:
-- Centralize member add/edit writes while keeping member_directory as a
-- compatibility record during rollout.

set check_function_bodies = off;

create or replace function public.upsert_member_person_membership(
  p_member_directory_id uuid default null,
  p_church_id uuid default null,
  p_department_id uuid default null,
  p_full_name text default null,
  p_phone text default null,
  p_group_name text default null,
  p_role_in_group text default 'member',
  p_family_name text default null,
  p_spouse_name text default null,
  p_children_info text default null,
  p_birth_date date default null,
  p_wedding_anniversary date default null,
  p_notes text default null,
  p_avatar_url text default null,
  p_profile_id uuid default null,
  p_person_id uuid default null,
  p_is_active boolean default true
)
returns public.member_directory
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.member_directory%rowtype;
  v_saved public.member_directory%rowtype;
  v_church_id uuid;
  v_department_id uuid;
  v_full_name text;
  v_phone text;
  v_group_name text;
  v_role_in_group text;
  v_profile_church_id uuid;
  v_person_id uuid;
begin
  if p_member_directory_id is not null then
    select *
    into v_existing
    from public.member_directory
    where id = p_member_directory_id;

    if not found then
      raise exception 'Member directory row % does not exist.', p_member_directory_id;
    end if;
  end if;

  v_church_id := coalesce(p_church_id, v_existing.church_id);
  v_department_id := coalesce(p_department_id, v_existing.department_id);
  v_full_name := nullif(btrim(coalesce(p_full_name, v_existing.full_name)), '');
  v_phone := public.phase2_normalize_phone(coalesce(p_phone, v_existing.phone));
  v_group_name := nullif(btrim(coalesce(p_group_name, v_existing.group_name)), '');
  v_role_in_group := case
    when coalesce(p_role_in_group, v_existing.role_in_group, 'member') = 'leader' then 'leader'
    else 'member'
  end;

  if v_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if v_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if v_full_name is null then
    raise exception 'full_name is required.';
  end if;

  if p_profile_id is not null then
    select church_id
    into v_profile_church_id
    from public.profiles
    where id = p_profile_id;

    if v_profile_church_id is null then
      raise exception 'Linked profile % does not exist.', p_profile_id;
    end if;

    if v_profile_church_id <> v_church_id then
      raise exception 'Linked profile belongs to another church.';
    end if;
  end if;

  v_person_id := public.phase2_upsert_person(
    v_church_id,
    coalesce(p_person_id, v_existing.person_id),
    p_profile_id,
    p_member_directory_id,
    v_full_name,
    v_phone
  );

  if p_member_directory_id is null then
    insert into public.member_directory (
      church_id,
      department_id,
      full_name,
      phone,
      group_name,
      role_in_group,
      family_name,
      spouse_name,
      children_info,
      birth_date,
      wedding_anniversary,
      notes,
      avatar_url,
      profile_id,
      person_id,
      is_linked,
      is_active,
      joined_at,
      left_at
    )
    values (
      v_church_id,
      v_department_id,
      v_full_name,
      v_phone,
      v_group_name,
      v_role_in_group,
      p_family_name,
      p_spouse_name,
      p_children_info,
      p_birth_date,
      p_wedding_anniversary,
      p_notes,
      p_avatar_url,
      p_profile_id,
      v_person_id,
      p_profile_id is not null,
      coalesce(p_is_active, true),
      now(),
      case when coalesce(p_is_active, true) then null else now() end
    )
    returning * into v_saved;
  else
    update public.member_directory
    set
      church_id = v_church_id,
      department_id = v_department_id,
      full_name = v_full_name,
      phone = v_phone,
      group_name = v_group_name,
      role_in_group = v_role_in_group,
      family_name = p_family_name,
      spouse_name = p_spouse_name,
      children_info = p_children_info,
      birth_date = p_birth_date,
      wedding_anniversary = p_wedding_anniversary,
      notes = p_notes,
      avatar_url = p_avatar_url,
      profile_id = p_profile_id,
      person_id = v_person_id,
      is_linked = p_profile_id is not null,
      is_active = coalesce(p_is_active, true),
      left_at = case
        when coalesce(p_is_active, true) then null
        else coalesce(v_existing.left_at, now())
      end
    where id = p_member_directory_id
    returning * into v_saved;
  end if;

  return v_saved;
end;
$$;

grant execute on function public.upsert_member_person_membership(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  date,
  date,
  text,
  text,
  uuid,
  uuid,
  boolean
) to authenticated, service_role;
