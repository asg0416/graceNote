-- App/admin member group move with an explicit effective week.
-- This is used for new-family climbing from the Flutter admin member detail.

set check_function_bodies = off;

create or replace function public.move_member_directory_to_group(
  p_member_directory_id uuid,
  p_source_group_id uuid,
  p_target_group_id uuid,
  p_effective_week_date date
)
returns public.member_directory
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.member_directory%rowtype;
  v_saved public.member_directory%rowtype;
  v_target_group public.groups%rowtype;
  v_effective_week date := public.phase3_week_start(coalesce(p_effective_week_date, current_date));
  v_effective_start timestamp with time zone;
  v_source_end timestamp with time zone;
  v_person_id uuid;
  v_target_membership_id uuid;
begin
  if p_member_directory_id is null then
    raise exception 'member_directory_id is required.';
  end if;

  if p_target_group_id is null then
    raise exception 'target_group_id is required.';
  end if;

  select *
  into v_member
  from public.member_directory
  where id = p_member_directory_id;

  if not found then
    raise exception 'Member directory row % does not exist.', p_member_directory_id;
  end if;

  select *
  into v_target_group
  from public.groups
  where id = p_target_group_id;

  if not found then
    raise exception 'Target group % does not exist.', p_target_group_id;
  end if;

  if v_target_group.church_id <> v_member.church_id
     or v_target_group.department_id <> v_member.department_id then
    raise exception 'Target group belongs to another church or department.';
  end if;

  v_effective_start := v_effective_week::timestamp with time zone;
  v_source_end := v_effective_start - interval '1 second';

  v_person_id := public.phase2_upsert_person(
    v_member.church_id,
    v_member.person_id,
    v_member.profile_id,
    v_member.id,
    v_member.full_name,
    v_member.phone
  );

  if p_source_group_id is not null then
    update public.memberships m
    set status = 'ended',
        ends_at = least(coalesce(m.ends_at, v_source_end), v_source_end),
        updated_at = now()
    where m.person_id = v_person_id
      and m.church_id = v_member.church_id
      and m.department_id = v_member.department_id
      and m.group_id = p_source_group_id
      and m.status = 'active'
      and coalesce(m.starts_at, v_effective_start) <= v_source_end;
  end if;

  select m.id
  into v_target_membership_id
  from public.memberships m
  where m.person_id = v_person_id
    and m.church_id = v_member.church_id
    and m.department_id = v_member.department_id
    and m.group_id = p_target_group_id
  order by
    case when m.status = 'active' then 0 else 1 end,
    m.updated_at desc nulls last,
    m.starts_at desc nulls last,
    m.id
  limit 1;

  if v_target_membership_id is null then
    insert into public.memberships (
      church_id,
      department_id,
      person_id,
      group_id,
      role,
      status,
      starts_at,
      ends_at,
      legacy_member_directory_id
    )
    values (
      v_member.church_id,
      v_member.department_id,
      v_person_id,
      p_target_group_id,
      coalesce(nullif(v_member.role_in_group, ''), 'member'),
      'active',
      v_effective_start,
      null,
      v_member.id
    );
  else
    update public.memberships
    set status = 'active',
        starts_at = v_effective_start,
        ends_at = null,
        legacy_member_directory_id = coalesce(legacy_member_directory_id, v_member.id),
        updated_at = now()
    where id = v_target_membership_id;
  end if;

  update public.member_directory
  set person_id = v_person_id,
      group_name = v_target_group.name,
      role_in_group = coalesce(nullif(role_in_group, ''), 'member'),
      is_active = true,
      left_at = null
  where id = v_member.id
  returning * into v_saved;

  return v_saved;
end;
$$;

grant execute on function public.move_member_directory_to_group(
  uuid,
  uuid,
  uuid,
  date
) to authenticated, service_role;
