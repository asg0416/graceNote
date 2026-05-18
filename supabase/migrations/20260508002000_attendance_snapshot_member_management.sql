-- Admin helpers for editing attendance roster snapshots like an Excel sheet.

create or replace function public.add_attendance_roster_snapshot_member(
  p_snapshot_id uuid,
  p_person_id uuid,
  p_group_id uuid default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot public.attendance_roster_snapshots%rowtype;
  v_person public.people%rowtype;
  v_group_name text;
  v_membership public.memberships%rowtype;
begin
  select * into v_snapshot
  from public.attendance_roster_snapshots
  where id = p_snapshot_id;

  if v_snapshot.id is null then
    raise exception 'snapshot not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_snapshot.church_id)
  ) then
    raise exception 'not allowed to edit attendance roster snapshot';
  end if;

  if v_snapshot.status = 'locked' then
    raise exception 'snapshot is locked';
  end if;

  select * into v_person
  from public.people
  where id = p_person_id
    and church_id = v_snapshot.church_id;

  if v_person.id is null then
    raise exception 'person not found in snapshot church';
  end if;

  if p_group_id is not null then
    select name into v_group_name
    from public.groups
    where id = p_group_id
      and department_id = v_snapshot.department_id
      and church_id = v_snapshot.church_id;

    if v_group_name is null then
      raise exception 'group not found in snapshot department';
    end if;
  end if;

  select *
    into v_membership
  from public.memberships m
  where m.person_id = p_person_id
    and m.church_id = v_snapshot.church_id
    and m.department_id = v_snapshot.department_id
    and (p_group_id is null or m.group_id = p_group_id)
  order by
    case when m.status = 'active' then 0 else 1 end,
    m.updated_at desc nulls last
  limit 1;

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
    source,
    reason
  )
  values (
    p_snapshot_id,
    p_person_id,
    v_membership.id,
    v_membership.legacy_member_directory_id,
    p_group_id,
    coalesce(v_membership.role, 'member'),
    coalesce(nullif(v_person.display_name, ''), '이름 없음'),
    v_group_name,
    'unknown',
    true,
    'manual_add',
    p_reason
  )
  on conflict (snapshot_id, person_id) do update
    set included = true,
        membership_id = excluded.membership_id,
        legacy_member_directory_id = coalesce(excluded.legacy_member_directory_id, attendance_roster_snapshot_members.legacy_member_directory_id),
        group_id = excluded.group_id,
        role = excluded.role,
        group_name = excluded.group_name,
        source = 'manual_add',
        reason = excluded.reason,
        updated_at = now();

  update public.attendance_roster_snapshots
     set status = 'admin_adjusted',
         source = 'manual',
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_snapshot_id;

  insert into public.attendance_roster_snapshot_events (
    snapshot_id,
    person_id,
    event_type,
    after,
    reason,
    created_by
  )
  values (
    p_snapshot_id,
    p_person_id,
    'member_added',
    jsonb_build_object('group_id', p_group_id, 'group_name', v_group_name),
    p_reason,
    auth.uid()
  );
end;
$$;

create or replace function public.load_group_roster_into_attendance_snapshot(
  p_snapshot_id uuid,
  p_group_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot public.attendance_roster_snapshots%rowtype;
  v_group public.groups%rowtype;
  v_inserted integer := 0;
begin
  select * into v_snapshot
  from public.attendance_roster_snapshots
  where id = p_snapshot_id;

  if v_snapshot.id is null then
    raise exception 'snapshot not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_snapshot.church_id)
  ) then
    raise exception 'not allowed to edit attendance roster snapshot';
  end if;

  if v_snapshot.status = 'locked' then
    raise exception 'snapshot is locked';
  end if;

  select * into v_group
  from public.groups
  where id = p_group_id
    and church_id = v_snapshot.church_id
    and department_id = v_snapshot.department_id;

  if v_group.id is null then
    raise exception 'group not found in snapshot department';
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
    source,
    reason
  )
  select distinct on (m.person_id)
    p_snapshot_id,
    m.person_id,
    m.id,
    m.legacy_member_directory_id,
    p_group_id,
    m.role,
    coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), nullif(p.display_name, ''), '이름 없음'),
    v_group.name,
    'unknown',
    true,
    'auto_membership',
    'load group roster'
  from public.memberships m
  join public.people p on p.id = m.person_id
  left join public.member_directory md on md.id = m.legacy_member_directory_id
  left join public.member_profiles mp on mp.person_id = m.person_id
  where m.church_id = v_snapshot.church_id
    and m.department_id = v_snapshot.department_id
    and m.group_id = p_group_id
    and m.status = 'active'
  order by
    m.person_id,
    case when m.role = 'leader' then 0 else 1 end,
    m.updated_at desc nulls last
  on conflict (snapshot_id, person_id) do update
    set included = true,
        membership_id = excluded.membership_id,
        legacy_member_directory_id = coalesce(excluded.legacy_member_directory_id, attendance_roster_snapshot_members.legacy_member_directory_id),
        group_id = excluded.group_id,
        role = excluded.role,
        group_name = excluded.group_name,
        source = excluded.source,
        reason = excluded.reason,
        updated_at = now();

  get diagnostics v_inserted = row_count;

  update public.attendance_roster_snapshots
     set status = 'admin_adjusted',
         source = 'manual',
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_snapshot_id;

  return v_inserted;
end;
$$;

grant execute on function public.add_attendance_roster_snapshot_member(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function public.load_group_roster_into_attendance_snapshot(uuid, uuid) to authenticated, service_role;
