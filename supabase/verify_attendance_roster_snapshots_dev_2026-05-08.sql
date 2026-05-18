-- Dev verification for attendance roster snapshot schema/RPCs.
-- This script intentionally rolls back generated snapshot rows.

\set ON_ERROR_STOP on

begin;

select
  'attendance_roster_snapshot_tables' as check_name,
  count(*) as table_count
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'attendance_roster_snapshots',
    'attendance_roster_snapshot_members',
    'attendance_roster_snapshot_events'
  );

create temp table verify_attendance_roster_context as
select
  d.id as department_id,
  w.id as week_id,
  w.week_date
from public.departments d
join public.weeks w on w.church_id = d.church_id
where exists (
  select 1
  from public.memberships m
  where m.department_id = d.id
    and m.church_id = d.church_id
    and m.status = 'active'
    and (m.starts_at is null or m.starts_at::date <= w.week_date)
    and (m.ends_at is null or m.ends_at::date >= w.week_date)
)
order by w.week_date desc
limit 1;

do $$
declare
  v_department_id uuid;
  v_week_id uuid;
  v_week_date date;
  v_snapshot_id uuid;
  v_expected_count integer;
  v_actual_count integer;
  v_member_id uuid;
  v_status text;
begin
  select department_id, week_id, week_date
    into v_department_id, v_week_id, v_week_date
  from verify_attendance_roster_context
  limit 1;

  if v_department_id is null then
    raise exception 'No department/week with active memberships found for verification';
  end if;

  v_snapshot_id := public.ensure_attendance_roster_snapshot(v_department_id, v_week_id);

  select count(distinct m.person_id)
    into v_expected_count
  from public.memberships m
  where m.department_id = v_department_id
    and m.status = 'active'
    and (m.starts_at is null or m.starts_at::date <= v_week_date)
    and (m.ends_at is null or m.ends_at::date >= v_week_date);

  select count(*)
    into v_actual_count
  from public.attendance_roster_snapshot_members sm
  where sm.snapshot_id = v_snapshot_id
    and sm.included = true;

  if v_expected_count <> v_actual_count then
    raise exception 'Snapshot member count mismatch. expected %, actual %', v_expected_count, v_actual_count;
  end if;

  select id
    into v_member_id
  from public.attendance_roster_snapshot_members
  where snapshot_id = v_snapshot_id
  limit 1;

  if v_member_id is not null then
    perform public.set_attendance_roster_snapshot_member_status(v_member_id, 'absent', 'verify status update');

    select attendance_status
      into v_status
    from public.attendance_roster_snapshot_members
    where id = v_member_id;

    if v_status <> 'absent' then
      raise exception 'Snapshot member status update failed';
    end if;

    perform public.set_attendance_roster_snapshot_member_included(v_member_id, false, 'verify exclude');

    if exists (
      select 1
      from public.attendance_roster_snapshot_members
      where id = v_member_id
        and included = true
    ) then
      raise exception 'Snapshot member include update failed';
    end if;
  end if;

  raise notice 'Attendance roster snapshot verification passed. snapshot %, expected members %', v_snapshot_id, v_expected_count;
end $$;

rollback;
