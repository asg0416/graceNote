-- Bulk-load current active rosters for groups that have no included members in
-- a week+department attendance snapshot. This supports historical denominator
-- repair without forcing admins to load each unsubmitted group one by one.

create or replace function public.load_missing_group_rosters_into_attendance_snapshot(
  p_snapshot_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot public.attendance_roster_snapshots%rowtype;
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

  with missing_groups as (
    select g.id, g.name
    from public.groups g
    where g.church_id = v_snapshot.church_id
      and g.department_id = v_snapshot.department_id
      and coalesce(g.is_active, true) = true
      and not exists (
        select 1
        from public.attendance_roster_snapshot_members sm
        where sm.snapshot_id = p_snapshot_id
          and sm.group_id = g.id
          and sm.included = true
      )
  )
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
    m.group_id,
    m.role,
    coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), nullif(p.display_name, ''), '이름 없음'),
    mg.name,
    'unknown',
    true,
    'auto_membership',
    'bulk load missing group rosters'
  from missing_groups mg
  join public.memberships m on m.group_id = mg.id
  join public.people p on p.id = m.person_id
  left join public.member_directory md on md.id = m.legacy_member_directory_id
  left join public.member_profiles mp on mp.person_id = m.person_id
  where m.church_id = v_snapshot.church_id
    and m.department_id = v_snapshot.department_id
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

  if v_inserted > 0 then
    update public.attendance_roster_snapshots
       set status = 'admin_adjusted',
           source = 'manual',
           updated_at = now(),
           updated_by = auth.uid()
     where id = p_snapshot_id;

    insert into public.attendance_roster_snapshot_events (
      snapshot_id,
      event_type,
      after,
      reason,
      created_by
    )
    values (
      p_snapshot_id,
      'member_added',
      jsonb_build_object('count', v_inserted, 'mode', 'bulk_missing_group_rosters'),
      'bulk load missing group rosters',
      auth.uid()
    );
  end if;

  return v_inserted;
end;
$$;

grant execute on function public.load_missing_group_rosters_into_attendance_snapshot(uuid)
  to authenticated, service_role;
