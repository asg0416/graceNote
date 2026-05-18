-- When a week already has an auto-generated snapshot member for a person,
-- submitted attendance for that same person must still win if the snapshot row
-- has not been manually edited. This keeps historical/deleted-group attendance
-- visible without duplicating the person in the department denominator.

create or replace function public.ensure_attendance_roster_snapshot(
  p_department_id uuid,
  p_week_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot_id uuid;
  v_week_date date;
  v_church_id uuid;
  v_created boolean := false;
begin
  select w.week_date, d.church_id
    into v_week_date, v_church_id
  from public.weeks w
  join public.departments d on d.id = p_department_id
  where w.id = p_week_id;

  if v_week_date is null or v_church_id is null then
    raise exception 'week or department not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_church_id)
    or v_church_id = public.get_my_church_id()
  ) then
    raise exception 'not allowed to read attendance roster snapshot';
  end if;

  insert into public.attendance_roster_snapshots (
    church_id,
    department_id,
    week_id,
    status,
    source,
    generated_by,
    updated_by
  )
  values (
    v_church_id,
    p_department_id,
    p_week_id,
    'system_generated',
    'auto',
    auth.uid(),
    auth.uid()
  )
  on conflict (department_id, week_id) do update
    set updated_at = public.attendance_roster_snapshots.updated_at
  returning id, (xmax = 0) into v_snapshot_id, v_created;

  if v_created then
    insert into public.attendance_roster_snapshot_events (
      snapshot_id,
      event_type,
      after,
      created_by
    )
    values (
      v_snapshot_id,
      'snapshot_created',
      jsonb_build_object(
        'department_id', p_department_id,
        'week_id', p_week_id,
        'week_date', v_week_date
      ),
      auth.uid()
    );
  end if;

  insert into public.attendance_roster_snapshot_members (
    snapshot_id,
    person_id,
    membership_id,
    legacy_member_directory_id,
    group_id,
    role,
    display_name,
    group_name,
    attendance_status,
    included,
    source
  )
  select distinct on (m.person_id)
    v_snapshot_id,
    m.person_id,
    m.id,
    m.legacy_member_directory_id,
    m.group_id,
    m.role,
    coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), nullif(p.display_name, ''), '이름 없음') as display_name,
    g.name as group_name,
    'unknown',
    true,
    'auto_membership'
  from public.memberships m
  join public.people p on p.id = m.person_id
  left join public.member_directory md on md.id = m.legacy_member_directory_id
  left join public.member_profiles mp on mp.person_id = m.person_id
  left join public.groups g on g.id = m.group_id
  where m.department_id = p_department_id
    and m.church_id = v_church_id
    and m.status = 'active'
    and (m.starts_at is null or m.starts_at::date <= v_week_date)
    and (m.ends_at is null or m.ends_at::date >= v_week_date)
  order by
    m.person_id,
    case when m.role = 'leader' then 0 else 1 end,
    case when m.group_id is not null then 0 else 1 end,
    m.starts_at nulls first,
    m.created_at nulls first
  on conflict (snapshot_id, person_id) do nothing;

  insert into public.attendance_roster_snapshot_members (
    snapshot_id,
    person_id,
    membership_id,
    legacy_member_directory_id,
    group_id,
    role,
    display_name,
    group_name,
    attendance_status,
    included,
    source
  )
  select distinct on (coalesce(a.person_id, md.person_id, mp.person_id))
    v_snapshot_id,
    coalesce(a.person_id, md.person_id, mp.person_id) as person_id,
    coalesce(a.membership_id, m.id) as membership_id,
    a.directory_member_id,
    coalesce(a.recorded_group_id, a.group_id, g.id),
    coalesce(m.role, md.role_in_group, 'member') as role,
    coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), p.display_name, '이름 없음') as display_name,
    coalesce(g.name, md.group_name) as group_name,
    case
      when a.status in ('present', 'late', 'absent') then a.status
      else 'unknown'
    end as attendance_status,
    true,
    'attendance_snapshot'
  from public.attendance a
  join public.groups g on g.id = coalesce(a.recorded_group_id, a.group_id)
  left join public.member_directory md on md.id = a.directory_member_id
  left join public.member_profiles mp on mp.member_directory_id = a.directory_member_id
  left join public.people p on p.id = coalesce(a.person_id, md.person_id, mp.person_id)
  left join public.memberships m
    on m.person_id = coalesce(a.person_id, md.person_id, mp.person_id)
   and m.department_id = p_department_id
   and m.church_id = v_church_id
   and (
     m.id = a.membership_id
     or m.legacy_member_directory_id = a.directory_member_id
     or m.group_id = coalesce(a.recorded_group_id, a.group_id, g.id)
   )
  where a.week_id = p_week_id
    and g.department_id = p_department_id
    and coalesce(a.person_id, md.person_id, mp.person_id) is not null
  order by
    coalesce(a.person_id, md.person_id, mp.person_id),
    case when a.status in ('present', 'late') then 0 else 1 end,
    a.updated_at desc nulls last,
    a.created_at desc nulls last
  on conflict (snapshot_id, person_id) do update
    set
      membership_id = coalesce(excluded.membership_id, attendance_roster_snapshot_members.membership_id),
      legacy_member_directory_id = coalesce(excluded.legacy_member_directory_id, attendance_roster_snapshot_members.legacy_member_directory_id),
      group_id = coalesce(excluded.group_id, attendance_roster_snapshot_members.group_id),
      role = coalesce(excluded.role, attendance_roster_snapshot_members.role),
      display_name = coalesce(nullif(excluded.display_name, ''), attendance_roster_snapshot_members.display_name),
      group_name = coalesce(nullif(excluded.group_name, ''), attendance_roster_snapshot_members.group_name),
      attendance_status = excluded.attendance_status,
      included = true,
      source = 'attendance_snapshot'
    where attendance_roster_snapshot_members.source = 'auto_membership'
      and attendance_roster_snapshot_members.attendance_status = 'unknown'
      and attendance_roster_snapshot_members.reason is null;

  return v_snapshot_id;
end;
$$;
