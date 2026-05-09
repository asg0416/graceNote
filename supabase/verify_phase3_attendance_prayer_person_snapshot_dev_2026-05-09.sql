-- Phase 3 Task 1 verification:
-- Run on DEV only after applying
-- supabase/migrations/20260509000000_phase3_attendance_prayer_person_snapshot.sql.

with checks as (
  select
    'attendance_missing_person_id' as check_name,
    count(*)::bigint as issue_count
  from public.attendance a
  where a.directory_member_id is not null
    and a.person_id is null

  union all

  select
    'prayer_entries_missing_person_id' as check_name,
    count(*)::bigint as issue_count
  from public.prayer_entries p
  where p.directory_member_id is not null
    and p.person_id is null

  union all

  select
    'attendance_missing_recorded_group_id' as check_name,
    count(*)::bigint as issue_count
  from public.attendance a
  where a.group_id is not null
    and a.recorded_group_id is null

  union all

  select
    'prayer_entries_missing_recorded_group_id' as check_name,
    count(*)::bigint as issue_count
  from public.prayer_entries p
  where p.group_id is not null
    and p.recorded_group_id is null

  union all

  select
    'attendance_person_directory_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance a
  join public.member_profiles mp
    on mp.member_directory_id = a.directory_member_id
  where a.person_id is not null
    and mp.person_id is not null
    and a.person_id <> mp.person_id

  union all

  select
    'prayer_entries_person_directory_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.prayer_entries p
  join public.member_profiles mp
    on mp.member_directory_id = p.directory_member_id
  where p.person_id is not null
    and mp.person_id is not null
    and p.person_id <> mp.person_id

  union all

  select
    'attendance_membership_person_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.attendance a
  join public.memberships m
    on m.id = a.membership_id
  where a.person_id is not null
    and m.person_id <> a.person_id

  union all

  select
    'prayer_entries_membership_person_mismatch' as check_name,
    count(*)::bigint as issue_count
  from public.prayer_entries p
  join public.memberships m
    on m.id = p.membership_id
  where p.person_id is not null
    and m.person_id <> p.person_id
)
select *
from checks
order by check_name;

-- Optional diagnostics: rows that still cannot be person-linked because their
-- legacy directory/profile bridge is absent. These are expected only if there
-- are documented orphan records from old data.
select
  'attendance_unlinked_sample' as diagnostic,
  a.id,
  a.week_id,
  a.directory_member_id,
  a.group_id,
  a.status
from public.attendance a
where a.directory_member_id is not null
  and a.person_id is null
limit 20;

select
  'prayer_entries_unlinked_sample' as diagnostic,
  p.id,
  p.week_id,
  p.directory_member_id,
  p.group_id,
  p.status
from public.prayer_entries p
where p.directory_member_id is not null
  and p.person_id is null
limit 20;
