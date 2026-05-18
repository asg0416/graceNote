-- Pre-production automatic repair candidate details.
-- Read-only. This does not mutate data; it lists deterministic drift that can
-- be converted into an approved prod repair SQL after clone verification.

with candidates as (
  select
    'inactive_directory_still_has_active_membership' as repair_type,
    md.church_id,
    md.department_id,
    m.group_id,
    m.person_id,
    md.id as legacy_member_directory_id,
    m.id as membership_id,
    jsonb_build_object(
      'expected_action', 'end membership or restore directory intentionally',
      'member_directory_is_active', md.is_active,
      'membership_status', m.status,
      'member_name', md.full_name,
      'phone', md.phone
    ) as details
  from public.member_directory md
  join public.memberships m on m.legacy_member_directory_id = md.id
  where md.is_active = false
    and m.status = 'active'

  union all

  select
    'inactive_group_member_still_has_active_membership',
    g.church_id,
    g.department_id,
    g.id,
    m.person_id,
    gm.member_directory_id,
    m.id,
    jsonb_build_object(
      'expected_action', 'end membership or restore group_member intentionally',
      'group_member_is_active', gm.is_active,
      'membership_status', m.status,
      'group_name', g.name
    )
  from public.group_members gm
  join public.memberships m on m.legacy_group_member_id = gm.id
  join public.groups g on g.id = gm.group_id
  where gm.is_active = false
    and m.status = 'active'

  union all

  select
    'active_membership_points_to_inactive_group',
    m.church_id,
    m.department_id,
    m.group_id,
    m.person_id,
    m.legacy_member_directory_id,
    m.id,
    jsonb_build_object(
      'expected_action', 'end membership or reactivate group intentionally',
      'group_name', g.name,
      'group_is_active', g.is_active,
      'membership_status', m.status
    )
  from public.memberships m
  join public.groups g on g.id = m.group_id
  where m.status = 'active'
    and coalesce(g.is_active, true) = false

  union all

  select
    'active_membership_points_to_inactive_department',
    m.church_id,
    m.department_id,
    m.group_id,
    m.person_id,
    m.legacy_member_directory_id,
    m.id,
    jsonb_build_object(
      'expected_action', 'end membership or reactivate department intentionally',
      'department_name', d.name,
      'department_is_active', d.is_active,
      'membership_status', m.status
    )
  from public.memberships m
  join public.departments d on d.id = m.department_id
  where m.status = 'active'
    and coalesce(d.is_active, true) = false

  union all

  select
    'active_membership_legacy_directory_scope_mismatch',
    m.church_id,
    m.department_id,
    m.group_id,
    m.person_id,
    md.id,
    m.id,
    jsonb_build_object(
      'expected_action', 'align legacy directory scope to membership or split row after review',
      'membership_church_id', m.church_id,
      'directory_church_id', md.church_id,
      'membership_department_id', m.department_id,
      'directory_department_id', md.department_id,
      'member_name', md.full_name
    )
  from public.memberships m
  join public.member_directory md on md.id = m.legacy_member_directory_id
  where m.status = 'active'
    and (
      m.church_id <> md.church_id
      or m.department_id is distinct from md.department_id
    )

  union all

  select
    'active_membership_legacy_person_mismatch',
    m.church_id,
    m.department_id,
    m.group_id,
    m.person_id,
    m.legacy_member_directory_id,
    m.id,
    jsonb_build_object(
      'expected_action', 'link membership to member_profile person or repair member_profile after clone review',
      'membership_person_id', m.person_id,
      'member_profile_person_id', mp.person_id,
      'member_profile_id', mp.id,
      'member_name', mp.full_name
    )
  from public.memberships m
  join public.member_profiles mp on mp.member_directory_id = m.legacy_member_directory_id
  where m.status = 'active'
    and mp.person_id <> m.person_id
)
select
  c.repair_type,
  ch.name as church_name,
  d.name as department_name,
  g.name as group_name,
  c.person_id,
  c.legacy_member_directory_id,
  c.membership_id,
  c.details
from candidates c
left join public.churches ch on ch.id = c.church_id
left join public.departments d on d.id = c.department_id
left join public.groups g on g.id = c.group_id
order by c.repair_type, ch.name nulls last, d.name nulls last, g.name nulls last;
