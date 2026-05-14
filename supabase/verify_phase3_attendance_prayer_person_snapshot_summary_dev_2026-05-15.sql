-- Query-compatible summary gate for Phase 3 attendance/prayer person snapshots.
-- This file intentionally contains one statement so it can run through
-- `supabase db query --file`.

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
