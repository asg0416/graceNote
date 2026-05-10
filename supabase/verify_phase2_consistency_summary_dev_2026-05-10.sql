-- Phase 2 consistency summary gate.
-- This file intentionally returns one result set so it works with
-- `supabase db query`, which only prints the last statement result.

with expected_people_from_directory as (
  select distinct coalesce(md.person_id, p.person_id, md.profile_id, md.id) as person_id
  from public.member_directory md
  left join public.profiles p on p.id = md.profile_id
  where md.church_id is not null
),
expected_people_from_profiles as (
  select distinct coalesce(p.person_id, p.id) as person_id
  from public.profiles p
  where p.church_id is not null
),
expected_people_from_orphan_group_members as (
  select distinct gm.member_directory_id as person_id
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  left join public.member_directory md on md.id = gm.member_directory_id
  left join public.profiles p on p.id = gm.profile_id
  where g.church_id is not null
    and gm.profile_id is null
    and gm.member_directory_id is not null
    and md.id is null
    and p.id is null
),
expected_people as (
  select person_id from expected_people_from_directory
  union
  select person_id from expected_people_from_profiles
  union
  select person_id from expected_people_from_orphan_group_members
),
expected_group_members as (
  select gm.id
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  left join public.member_directory md on md.id = gm.member_directory_id
  left join public.profiles p on p.id = gm.profile_id
  where g.church_id is not null
    and coalesce(md.person_id, p.person_id, gm.profile_id, gm.member_directory_id) is not null
),
expected_directory_only_memberships as (
  select md.id
  from public.member_directory md
  join public.groups g
    on g.church_id = md.church_id
   and g.department_id = md.department_id
   and g.name = md.group_name
  where md.church_id is not null
    and md.group_name is not null
    and md.group_name <> ''
    and not exists (
      select 1
      from public.group_members gm
      where gm.member_directory_id = md.id
        and gm.is_active = true
    )
),
expected_directory_members as (
  select md.id
  from public.member_directory md
  where md.church_id is not null
),
checks as (
  select
    'people_expected_missing' as check_name,
    count(*)::bigint as issue_count
  from expected_people ep
  left join public.people p on p.id = ep.person_id
  where ep.person_id is not null
    and p.id is null

  union all

  select
    'group_members_missing_memberships' as check_name,
    count(*)::bigint as issue_count
  from expected_group_members egm
  left join public.memberships m on m.legacy_group_member_id = egm.id
  where m.id is null

  union all

  select
    'directory_only_missing_memberships' as check_name,
    count(*)::bigint as issue_count
  from expected_directory_only_memberships edom
  left join public.memberships m
    on m.legacy_member_directory_id = edom.id
   and m.legacy_group_member_id is null
  where m.id is null

  union all

  select
    'member_directory_missing_member_profiles' as check_name,
    count(*)::bigint as issue_count
  from expected_directory_members edm
  left join public.member_profiles mp on mp.member_directory_id = edm.id
  where mp.id is null

  union all

  select
    'active_group_member_status_mismatches' as check_name,
    count(*)::bigint as issue_count
  from public.group_members gm
  join public.memberships m on m.legacy_group_member_id = gm.id
  left join public.member_directory md on md.id = gm.member_directory_id
  where coalesce(gm.is_active, true) = true
    and (gm.member_directory_id is null or md.id is not null)
    and m.status <> 'active'

  union all

  select
    'inactive_group_member_status_mismatches' as check_name,
    count(*)::bigint as issue_count
  from public.group_members gm
  join public.memberships m on m.legacy_group_member_id = gm.id
  where coalesce(gm.is_active, true) = false
    and m.status not in ('inactive', 'ended')

  union all

  select
    'stale_active_group_member_memberships_not_ended' as check_name,
    count(*)::bigint as issue_count
  from public.group_members gm
  join public.memberships m on m.legacy_group_member_id = gm.id
  left join public.member_directory md on md.id = gm.member_directory_id
  where gm.member_directory_id is not null
    and md.id is null
    and coalesce(gm.is_active, true) = true
    and m.status <> 'ended'

  union all

  select
    'role_mismatches' as check_name,
    count(*)::bigint as issue_count
  from public.group_members gm
  join public.memberships m on m.legacy_group_member_id = gm.id
  where (
      case when gm.role_in_group = 'leader' then 'leader' else 'member' end
    ) <> m.role

  union all

  select
    'memberships_missing_people' as check_name,
    count(*)::bigint as issue_count
  from public.memberships m
  left join public.people p on p.id = m.person_id
  where p.id is null

  union all

  select
    'member_profiles_missing_people' as check_name,
    count(*)::bigint as issue_count
  from public.member_profiles mp
  left join public.people p on p.id = mp.person_id
  where p.id is null

  union all

  select
    'identity_candidate_same_church_phone' as check_name,
    count(*)::bigint as issue_count
  from (
    select 1
    from public.people
    where normalized_phone is not null
    group by church_id, normalized_phone
    having count(*) > 1
  ) duplicates
)
select *
from checks
order by check_name;
