-- Prod clone backfill repair:
-- Ensure legacy rows that existed before Phase 2/3 triggers are fully represented
-- in people/member_profiles/memberships and then refill attendance/prayer snapshots.

set check_function_bodies = off;

with seeded_profiles as (
  select
    p.*,
    public.phase2_upsert_person(
      p.church_id,
      p.person_id,
      p.id,
      null,
      p.full_name,
      p.phone
    ) as resolved_person_id
  from public.profiles p
  where p.church_id is not null
)
insert into public.member_profiles (
  person_id,
  profile_id,
  full_name,
  phone,
  avatar_url
)
select
  sp.resolved_person_id,
  sp.id,
  sp.full_name,
  sp.phone,
  sp.avatar_url
from seeded_profiles sp
where not exists (
  select 1
  from public.member_profiles mp
  where mp.profile_id = sp.id
    and mp.member_directory_id is null
);

with seeded_directory as (
  select
    md.*,
    public.phase2_upsert_person(
      md.church_id,
      md.person_id,
      case when p.church_id = md.church_id then md.profile_id else null end,
      md.id,
      md.full_name,
      md.phone
    ) as resolved_person_id
  from public.member_directory md
  left join public.profiles p on p.id = md.profile_id
  where md.church_id is not null
)
insert into public.member_profiles (
  person_id,
  profile_id,
  member_directory_id,
  full_name,
  phone,
  avatar_url,
  family_name
)
select
  sd.resolved_person_id,
  case when p.church_id = sd.church_id then sd.profile_id else null end,
  sd.id,
  sd.full_name,
  sd.phone,
  sd.avatar_url,
  sd.family_name
from seeded_directory sd
left join public.profiles p on p.id = sd.profile_id
on conflict (member_directory_id) do update set
  person_id = excluded.person_id,
  profile_id = excluded.profile_id,
  full_name = excluded.full_name,
  phone = excluded.phone,
  avatar_url = excluded.avatar_url,
  family_name = excluded.family_name,
  updated_at = now();

insert into public.person_identifiers (
  person_id,
  kind,
  value,
  source_table,
  source_id,
  is_primary
)
select
  mp.person_id,
  'legacy_directory',
  mp.member_directory_id::text,
  'member_directory',
  mp.member_directory_id,
  false
from public.member_profiles mp
where mp.member_directory_id is not null
on conflict do nothing;

insert into public.person_identifiers (
  person_id,
  kind,
  value,
  source_table,
  source_id,
  is_primary
)
select
  mp.person_id,
  'legacy_profile',
  mp.profile_id::text,
  'profiles',
  mp.profile_id,
  false
from public.member_profiles mp
where mp.profile_id is not null
on conflict do nothing;

with seeded_group_members as (
  select
    gm.*,
    g.church_id,
    g.department_id,
    md.id as directory_id,
    md.person_id as directory_person_id,
    md.full_name as directory_full_name,
    md.phone as directory_phone,
    p.person_id as profile_person_id,
    p.full_name as profile_full_name,
    p.phone as profile_phone,
    case when p.church_id = g.church_id then gm.profile_id else null end as safe_profile_id,
    public.phase2_upsert_person(
      g.church_id,
      coalesce(md.person_id, case when p.church_id = g.church_id then p.person_id else null end),
      case when p.church_id = g.church_id then gm.profile_id else null end,
      gm.member_directory_id,
      coalesce(md.full_name, p.full_name, '[legacy missing member_directory]'),
      coalesce(md.phone, p.phone)
    ) as resolved_person_id
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  left join public.member_directory md on md.id = gm.member_directory_id
  left join public.profiles p on p.id = gm.profile_id
  where g.church_id is not null
    and coalesce(md.person_id, p.person_id, gm.profile_id, gm.member_directory_id) is not null
)
insert into public.memberships (
  person_id,
  church_id,
  department_id,
  group_id,
  role,
  status,
  starts_at,
  ends_at,
  legacy_group_member_id,
  legacy_member_directory_id
)
select
  sgm.resolved_person_id,
  sgm.church_id,
  sgm.department_id,
  sgm.group_id,
  case when sgm.role_in_group = 'leader' then 'leader' else 'member' end,
  case
    when sgm.member_directory_id is not null and sgm.directory_id is null then 'ended'
    when coalesce(sgm.is_active, true) then 'active'
    else 'inactive'
  end,
  coalesce(sgm.joined_at, now()),
  case
    when sgm.member_directory_id is not null and sgm.directory_id is null then now()
    when coalesce(sgm.is_active, true) then null
    else now()
  end,
  sgm.id,
  sgm.directory_id
from seeded_group_members sgm
on conflict (legacy_group_member_id) do update set
  person_id = excluded.person_id,
  church_id = excluded.church_id,
  department_id = excluded.department_id,
  group_id = excluded.group_id,
  role = excluded.role,
  status = excluded.status,
  ends_at = excluded.ends_at,
  legacy_member_directory_id = excluded.legacy_member_directory_id,
  updated_at = now();

with resolved_attendance as (
  select
    a.id,
    a.person_id as current_person_id,
    a.membership_id as current_membership_id,
    a.recorded_group_id as current_recorded_group_id,
    a.recorded_department_id as current_recorded_department_id,
    a.group_id as legacy_group_id,
    r.person_id,
    r.membership_id,
    r.group_id,
    r.department_id
  from public.attendance a
  cross join lateral public.phase3_resolve_membership_snapshot(
    a.group_member_id,
    a.directory_member_id,
    a.group_id,
    null
  ) r
  where a.directory_member_id is not null
    and (
      a.person_id is null
      or a.membership_id is null
      or a.recorded_group_id is null
      or a.recorded_department_id is null
    )
)
update public.attendance a
set
  person_id = coalesce(ra.current_person_id, ra.person_id),
  membership_id = coalesce(ra.current_membership_id, ra.membership_id),
  recorded_group_id = coalesce(ra.current_recorded_group_id, ra.group_id, ra.legacy_group_id),
  recorded_department_id = coalesce(ra.current_recorded_department_id, ra.department_id)
from resolved_attendance ra
where a.id = ra.id;

with resolved_prayer_entries as (
  select
    p.id,
    p.person_id as current_person_id,
    p.membership_id as current_membership_id,
    p.recorded_group_id as current_recorded_group_id,
    p.recorded_department_id as current_recorded_department_id,
    p.group_id as legacy_group_id,
    r.person_id,
    r.membership_id,
    r.group_id,
    r.department_id
  from public.prayer_entries p
  cross join lateral public.phase3_resolve_membership_snapshot(
    null,
    p.directory_member_id,
    p.group_id,
    p.member_id
  ) r
  where p.directory_member_id is not null
    and (
      p.person_id is null
      or p.membership_id is null
      or p.recorded_group_id is null
      or p.recorded_department_id is null
    )
)
update public.prayer_entries p
set
  person_id = coalesce(rp.current_person_id, rp.person_id),
  membership_id = coalesce(rp.current_membership_id, rp.membership_id),
  recorded_group_id = coalesce(rp.current_recorded_group_id, rp.group_id, rp.legacy_group_id),
  recorded_department_id = coalesce(rp.current_recorded_department_id, rp.department_id)
from resolved_prayer_entries rp
where p.id = rp.id;
