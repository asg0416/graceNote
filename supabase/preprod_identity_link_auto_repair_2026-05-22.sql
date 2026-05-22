-- Pre-production identity link automatic repair for GraceNote person-structure rollout.
-- Mutating. Run only on dev/staging/prod clone after reading the matching audit output.
--
-- Deterministic repairs only:
-- 1. If a profile email matches an auth.users email, the profile id differs,
--    and the auth uid does not already have a profile row, copy the source
--    profile to the auth uid and move same-church references only.
-- 2. Detach stale cross-church profile links from legacy/person bridge rows.
--
-- This deliberately does not merge same-name/same-phone people, duplicate
-- emails with an existing target profile, or same-church person mismatches.

begin;

drop table if exists pg_temp._identity_email_repairs;
drop table if exists pg_temp._identity_repair_counts;

create temp table _identity_repair_counts (
  repair_type text primary key,
  row_count bigint not null
) on commit drop;

create temp table _identity_email_repairs on commit drop as
select
  p.id as source_profile_id,
  u.id as target_profile_id,
  p.church_id
from public.profiles p
join auth.users u on lower(u.email) = lower(p.email)
left join public.profiles target_profile on target_profile.id = u.id
where p.email is not null
  and p.id <> u.id
  and target_profile.id is null;

insert into public.profiles (
  id,
  church_id,
  full_name,
  role,
  avatar_url,
  created_at,
  department_id,
  family_id,
  spouse_id,
  admin_status,
  is_master,
  is_onboarding_complete,
  phone,
  wedding_anniversary,
  children_info,
  notes,
  last_notice_checked_at,
  email,
  person_id
)
select
  r.target_profile_id,
  p.church_id,
  p.full_name,
  p.role,
  p.avatar_url,
  p.created_at,
  p.department_id,
  p.family_id,
  p.spouse_id,
  p.admin_status,
  p.is_master,
  p.is_onboarding_complete,
  p.phone,
  p.wedding_anniversary,
  p.children_info,
  p.notes,
  p.last_notice_checked_at,
  p.email,
  p.person_id
from _identity_email_repairs r
join public.profiles p on p.id = r.source_profile_id
on conflict (id) do nothing;

insert into _identity_repair_counts
select 'profile_email_auth_id_copy', count(*)::bigint
from _identity_email_repairs;

with moved as (
  update public.member_directory md
  set profile_id = r.target_profile_id,
      is_linked = true
  from _identity_email_repairs r
  where md.profile_id = r.source_profile_id
    and md.church_id = r.church_id
  returning md.id
)
insert into _identity_repair_counts
select 'member_directory_email_auth_id_relink', count(*)::bigint
from moved;

with moved as (
  update public.member_profiles mp
  set profile_id = r.target_profile_id
  from _identity_email_repairs r
  join public.member_directory md on md.profile_id = r.target_profile_id
  where mp.profile_id = r.source_profile_id
    and mp.member_directory_id = md.id
    and md.church_id = r.church_id
  returning mp.id
)
insert into _identity_repair_counts
select 'member_profiles_email_auth_id_relink', count(*)::bigint
from moved;

with moved as (
  update public.group_members gm
  set profile_id = r.target_profile_id
  from _identity_email_repairs r
  join public.groups g on g.church_id = r.church_id
  where gm.profile_id = r.source_profile_id
    and gm.group_id = g.id
  returning gm.id
)
insert into _identity_repair_counts
select 'group_members_email_auth_id_relink', count(*)::bigint
from moved;

with moved as (
  update public.people pe
  set primary_profile_id = r.target_profile_id
  from _identity_email_repairs r
  where pe.primary_profile_id = r.source_profile_id
    and pe.church_id = r.church_id
  returning pe.id
)
insert into _identity_repair_counts
select 'people_email_auth_id_relink', count(*)::bigint
from moved;

-- The legacy member_directory table has sync triggers that can propagate profile_id
-- changes back across same-person rows. Disable only those sync triggers during
-- the deterministic cross-church detach, then explicitly repair the bridge rows
-- below. The trigger DDL is transactional in Postgres.
alter table public.member_directory disable trigger on_member_data_update;
alter table public.member_directory disable trigger on_directory_group_change;
alter table public.member_directory disable trigger on_member_directory_membership_sync;
alter table public.member_directory disable trigger phase2_member_directory_sync;

with detached as (
  update public.member_directory md
  set profile_id = null,
      is_linked = false
  from public.profiles p
  where md.profile_id = p.id
    and md.church_id is not null
    and p.church_id is not null
    and md.church_id <> p.church_id
  returning md.id
)
insert into _identity_repair_counts
select 'member_directory_cross_church_profile_detach', count(*)::bigint
from detached;

alter table public.member_directory enable trigger on_member_data_update;
alter table public.member_directory enable trigger on_directory_group_change;
alter table public.member_directory enable trigger on_member_directory_membership_sync;
alter table public.member_directory enable trigger phase2_member_directory_sync;

with detached as (
  update public.member_profiles mp
  set profile_id = null
  from public.member_directory md,
       public.profiles p
  where mp.member_directory_id = md.id
    and mp.profile_id = p.id
    and md.church_id is not null
    and p.church_id is not null
    and md.church_id <> p.church_id
  returning mp.id
)
insert into _identity_repair_counts
select 'member_profiles_cross_church_profile_detach', count(*)::bigint
from detached;

with detached as (
  update public.group_members gm
  set profile_id = null
  from public.groups g,
       public.profiles p
  where gm.group_id = g.id
    and gm.profile_id = p.id
    and g.church_id is not null
    and p.church_id is not null
    and g.church_id <> p.church_id
  returning gm.id
)
insert into _identity_repair_counts
select 'group_members_cross_church_profile_detach', count(*)::bigint
from detached;

with detached as (
  update public.people pe
  set primary_profile_id = null
  from public.profiles p
  where pe.primary_profile_id = p.id
    and pe.church_id is not null
    and p.church_id is not null
    and pe.church_id <> p.church_id
  returning pe.id
)
insert into _identity_repair_counts
select 'people_cross_church_primary_profile_detach', count(*)::bigint
from detached;

select repair_type, row_count
from _identity_repair_counts
order by repair_type;

commit;
