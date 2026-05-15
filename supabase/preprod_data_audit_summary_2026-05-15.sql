-- Pre-production data audit summary for GraceNote person-structure rollout.
-- Read-only. Intended for a production clone/staging database after applying
-- the Phase 2/3 migration chain.
--
-- Output policy:
-- - action_type = auto_repair_candidate: deterministic consistency drift that
--   can usually be fixed by a targeted repair SQL after clone verification.
-- - action_type = manual_review: identity/people data that must not be merged
--   automatically.
-- - action_type = blocking_gate: integrity issue that should be 0 before prod cutover.

with checks as (
  select
    'blocking_gate' as action_type,
    'phase2_membership_missing_person' as check_name,
    count(*)::bigint as issue_count
  from public.memberships m
  left join public.people p on p.id = m.person_id
  where p.id is null

  union all

  select
    'blocking_gate',
    'phase2_member_profile_missing_person',
    count(*)::bigint
  from public.member_profiles mp
  left join public.people p on p.id = mp.person_id
  where p.id is null

  union all

  select
    'auto_repair_candidate',
    'active_group_member_missing_membership',
    count(*)::bigint
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  left join public.memberships m on m.legacy_group_member_id = gm.id
  where coalesce(gm.is_active, true) = true
    and coalesce(g.is_active, true) = true
    and m.id is null

  union all

  select
    'auto_repair_candidate',
    'active_directory_missing_member_profile',
    count(*)::bigint
  from public.member_directory md
  left join public.member_profiles mp on mp.member_directory_id = md.id
  where coalesce(md.is_active, true) = true
    and md.church_id is not null
    and mp.id is null

  union all

  select
    'auto_repair_candidate',
    'inactive_directory_still_has_active_membership',
    count(*)::bigint
  from public.member_directory md
  join public.memberships m on m.legacy_member_directory_id = md.id
  where md.is_active = false
    and m.status = 'active'

  union all

  select
    'auto_repair_candidate',
    'inactive_group_member_still_has_active_membership',
    count(*)::bigint
  from public.group_members gm
  join public.memberships m on m.legacy_group_member_id = gm.id
  where gm.is_active = false
    and m.status = 'active'

  union all

  select
    'auto_repair_candidate',
    'active_membership_points_to_inactive_group',
    count(*)::bigint
  from public.memberships m
  join public.groups g on g.id = m.group_id
  where m.status = 'active'
    and coalesce(g.is_active, true) = false

  union all

  select
    'auto_repair_candidate',
    'active_membership_points_to_inactive_department',
    count(*)::bigint
  from public.memberships m
  join public.departments d on d.id = m.department_id
  where m.status = 'active'
    and coalesce(d.is_active, true) = false

  union all

  select
    'auto_repair_candidate',
    'active_membership_legacy_directory_scope_mismatch',
    count(*)::bigint
  from public.memberships m
  join public.member_directory md on md.id = m.legacy_member_directory_id
  where m.status = 'active'
    and (
      m.church_id <> md.church_id
      or m.department_id is distinct from md.department_id
    )

  union all

  select
    'auto_repair_candidate',
    'active_membership_group_scope_mismatch',
    count(*)::bigint
  from public.memberships m
  join public.groups g on g.id = m.group_id
  where m.status = 'active'
    and (
      m.church_id <> g.church_id
      or m.department_id is distinct from g.department_id
    )

  union all

  select
    'auto_repair_candidate',
    'active_membership_legacy_person_mismatch',
    count(*)::bigint
  from public.memberships m
  join public.member_profiles mp on mp.member_directory_id = m.legacy_member_directory_id
  where m.status = 'active'
    and mp.person_id <> m.person_id

  union all

  select
    'auto_repair_candidate',
    'duplicate_active_membership_same_person_department_group',
    count(*)::bigint
  from (
    select person_id, department_id, group_id
    from public.memberships
    where status = 'active'
      and department_id is not null
    group by person_id, department_id, group_id
    having count(*) > 1
  ) duplicates

  union all

  select
    'auto_repair_candidate',
    'duplicate_active_group_member_same_directory_group',
    count(*)::bigint
  from (
    select member_directory_id, group_id
    from public.group_members
    where coalesce(is_active, true) = true
      and member_directory_id is not null
      and group_id is not null
    group by member_directory_id, group_id
    having count(*) > 1
  ) duplicates

  union all

  select
    'manual_review',
    'same_church_duplicate_people_phone',
    count(*)::bigint
  from (
    select church_id, normalized_phone
    from public.people
    where normalized_phone is not null
    group by church_id, normalized_phone
    having count(*) > 1
  ) duplicates

  union all

  select
    'manual_review',
    'same_church_active_directory_duplicate_phone',
    count(*)::bigint
  from (
    select
      church_id,
      regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') as normalized_phone
    from public.member_directory
    where coalesce(is_active, true) = true
      and nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '') is not null
    group by church_id, regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g')
    having count(distinct coalesce(person_id, profile_id, id)) > 1
  ) duplicates

  union all

  select
    'manual_review',
    'same_church_same_name_multi_people',
    count(*)::bigint
  from (
    select church_id, btrim(display_name) as display_name
    from public.people
    where nullif(btrim(display_name), '') is not null
    group by church_id, btrim(display_name)
    having count(*) > 1
  ) duplicates

  union all

  select
    'manual_review',
    'cross_church_same_phone_people',
    count(*)::bigint
  from (
    select normalized_phone
    from public.people
    where normalized_phone is not null
    group by normalized_phone
    having count(distinct church_id) > 1
  ) duplicates

  union all

  select
    'blocking_gate',
    'attendance_snapshot_duplicate_person_per_snapshot',
    count(*)::bigint
  from (
    select snapshot_id, person_id
    from public.attendance_roster_snapshot_members
    group by snapshot_id, person_id
    having count(*) > 1
  ) duplicates

  union all

  select
    'blocking_gate',
    'attendance_snapshot_person_church_mismatch',
    count(*)::bigint
  from public.attendance_roster_snapshot_members sm
  join public.attendance_roster_snapshots s on s.id = sm.snapshot_id
  join public.people p on p.id = sm.person_id
  where p.church_id <> s.church_id

  union all

  select
    'blocking_gate',
    'attendance_person_snapshot_missing',
    count(*)::bigint
  from public.attendance a
  where a.person_id is null

  union all

  select
    'blocking_gate',
    'prayer_person_snapshot_missing',
    count(*)::bigint
  from public.prayer_entries pe
  where pe.person_id is null
)
select action_type, check_name, issue_count
from checks
order by
  case action_type
    when 'blocking_gate' then 1
    when 'auto_repair_candidate' then 2
    else 3
  end,
  check_name;
