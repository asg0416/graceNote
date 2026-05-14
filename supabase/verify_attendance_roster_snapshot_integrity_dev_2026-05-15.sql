-- Dev verification for attendance roster snapshot integrity.
-- This is a read-only gate for the admin attendance dashboard source of truth.

with checks as (
  select
    'snapshot_members_missing_person' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  left join public.people p on p.id = sm.person_id
  where p.id is null

  union all

  select
    'snapshot_members_person_church_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  join public.attendance_roster_snapshots s on s.id = sm.snapshot_id
  join public.people p on p.id = sm.person_id
  where p.church_id <> s.church_id

  union all

  select
    'snapshot_members_membership_person_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  join public.memberships m on m.id = sm.membership_id
  where m.person_id <> sm.person_id

  union all

  select
    'snapshot_members_membership_scope_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  join public.attendance_roster_snapshots s on s.id = sm.snapshot_id
  join public.memberships m on m.id = sm.membership_id
  where m.church_id <> s.church_id
     or m.department_id <> s.department_id

  union all

  select
    'snapshot_members_group_scope_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  join public.attendance_roster_snapshots s on s.id = sm.snapshot_id
  join public.groups g on g.id = sm.group_id
  where g.church_id <> s.church_id
     or g.department_id <> s.department_id

  union all

  select
    'snapshot_members_legacy_directory_person_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  join public.member_profiles mp on mp.member_directory_id = sm.legacy_member_directory_id
  where sm.legacy_member_directory_id is not null
    and mp.person_id is not null
    and mp.person_id <> sm.person_id

  union all

  select
    'snapshot_members_legacy_directory_scope_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  join public.attendance_roster_snapshots s on s.id = sm.snapshot_id
  join public.member_directory md on md.id = sm.legacy_member_directory_id
  where sm.legacy_member_directory_id is not null
    and (
      md.church_id <> s.church_id
      or md.department_id <> s.department_id
    )

  union all

  select
    'snapshot_members_included_without_display_name' as check_name,
    count(*)::bigint as issue_count
  from public.attendance_roster_snapshot_members sm
  where sm.included = true
    and nullif(btrim(sm.display_name), '') is null

  union all

  select
    'snapshot_members_duplicate_person_per_snapshot' as check_name,
    count(*)::bigint as issue_count
  from (
    select snapshot_id, person_id
    from public.attendance_roster_snapshot_members
    group by snapshot_id, person_id
    having count(*) > 1
  ) duplicates
)
select *
from checks
order by check_name;
