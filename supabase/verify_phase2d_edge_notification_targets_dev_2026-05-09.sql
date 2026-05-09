-- Phase 2D Edge Function notification target verification.
-- Purpose:
--   notify-event and notify-scheduler now read notification targets from
--   active memberships first, with group_members as a fallback.
--   This query checks whether Phase 2 target sets match the legacy target sets.
--
-- Expected:
--   all mismatch_count values = 0
--
-- Safe:
--   read-only verification

with legacy_leader_profiles as (
  select distinct
    gm.group_id,
    gm.profile_id
  from public.group_members gm
  where gm.is_active = true
    and gm.role_in_group = 'leader'
    and gm.profile_id is not null
),
phase2_leader_profiles as (
  select distinct
    m.group_id,
    m.profile_id
  from public.memberships m
  where m.status = 'active'
    and m.role = 'leader'
    and m.profile_id is not null
),
legacy_active_profiles as (
  select distinct
    gm.group_id,
    gm.profile_id
  from public.group_members gm
  where gm.is_active = true
    and gm.profile_id is not null
),
phase2_active_profiles as (
  select distinct
    m.group_id,
    m.profile_id
  from public.memberships m
  where m.status = 'active'
    and m.profile_id is not null
),
legacy_leader_directory_ids as (
  select distinct
    gm.group_id,
    gm.member_directory_id
  from public.group_members gm
  where gm.is_active = true
    and gm.role_in_group = 'leader'
    and gm.member_directory_id is not null
),
phase2_leader_directory_ids as (
  select distinct
    m.group_id,
    m.legacy_member_directory_id as member_directory_id
  from public.memberships m
  where m.status = 'active'
    and m.role = 'leader'
    and m.legacy_member_directory_id is not null
),
checks as (
  select
    'leader_profiles_missing_in_phase2' as check_name,
    count(*) as mismatch_count
  from (
    select * from legacy_leader_profiles
    except
    select * from phase2_leader_profiles
  ) missing

  union all

  select
    'leader_profiles_extra_in_phase2' as check_name,
    count(*) as mismatch_count
  from (
    select * from phase2_leader_profiles
    except
    select * from legacy_leader_profiles
  ) extra

  union all

  select
    'active_profiles_missing_in_phase2' as check_name,
    count(*) as mismatch_count
  from (
    select * from legacy_active_profiles
    except
    select * from phase2_active_profiles
  ) missing

  union all

  select
    'active_profiles_extra_in_phase2' as check_name,
    count(*) as mismatch_count
  from (
    select * from phase2_active_profiles
    except
    select * from legacy_active_profiles
  ) extra

  union all

  select
    'leader_directory_ids_missing_in_phase2' as check_name,
    count(*) as mismatch_count
  from (
    select * from legacy_leader_directory_ids
    except
    select * from phase2_leader_directory_ids
  ) missing

  union all

  select
    'leader_directory_ids_extra_in_phase2' as check_name,
    count(*) as mismatch_count
  from (
    select * from phase2_leader_directory_ids
    except
    select * from legacy_leader_directory_ids
  ) extra
)
select *
from checks
order by check_name;
