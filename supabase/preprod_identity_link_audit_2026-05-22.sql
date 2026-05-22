-- Pre-production identity link audit for GraceNote person-structure rollout.
-- Read-only. Focuses on auth.users <-> profiles <-> legacy/member/person links.
--
-- Severity policy:
-- - blocking_gate: login or person ownership can break for an existing auth user.
-- - auto_repair_candidate: deterministic auth/profile drift that can be repaired
--   after clone/dev verification.
-- - manual_review: ambiguous identity data. Do not auto-merge.

with checks as (
  select
    'blocking_gate' as action_type,
    'auth_user_missing_profile' as check_name,
    count(*)::bigint as issue_count
  from auth.users u
  left join public.profiles p on p.id = u.id
  where p.id is null

  union all

  select
    'manual_review',
    'profile_without_auth_user',
    count(*)::bigint
  from public.profiles p
  left join auth.users u on u.id = p.id
  where u.id is null

  union all

  select
    'auto_repair_candidate',
    'profile_email_matches_auth_but_id_diff_target_missing',
    count(*)::bigint
  from public.profiles p
  join auth.users u on lower(u.email) = lower(p.email)
  left join public.profiles target_profile on target_profile.id = u.id
  where p.email is not null
    and p.id <> u.id
    and target_profile.id is null

  union all

  select
    'manual_review',
    'profile_email_matches_auth_but_id_diff_target_exists',
    count(*)::bigint
  from public.profiles p
  join auth.users u on lower(u.email) = lower(p.email)
  join public.profiles target_profile on target_profile.id = u.id
  where p.email is not null
    and p.id <> u.id

  union all

  select
    'manual_review',
    'profile_email_differs_from_auth_email',
    count(*)::bigint
  from public.profiles p
  join auth.users u on u.id = p.id
  where nullif(lower(coalesce(p.email, '')), '') is not null
    and nullif(lower(coalesce(u.email, '')), '') is not null
    and lower(p.email) <> lower(u.email)

  union all

  select
    'manual_review',
    'same_email_multiple_profiles',
    count(*)::bigint
  from (
    select lower(email) as email_key
    from public.profiles
    where nullif(lower(coalesce(email, '')), '') is not null
    group by lower(email)
    having count(*) > 1
  ) duplicates

  union all

  select
    'manual_review',
    'member_directory_profile_church_mismatch',
    count(*)::bigint
  from public.member_directory md
  join public.profiles p on p.id = md.profile_id
  where md.church_id is not null
    and p.church_id is not null
    and md.church_id <> p.church_id

  union all

  select
    'manual_review',
    'member_profiles_profile_church_mismatch',
    count(*)::bigint
  from public.member_profiles mp
  join public.member_directory md on md.id = mp.member_directory_id
  join public.profiles p on p.id = mp.profile_id
  where md.church_id is not null
    and p.church_id is not null
    and md.church_id <> p.church_id

  union all

  select
    'manual_review',
    'group_members_profile_church_mismatch',
    count(*)::bigint
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  join public.profiles p on p.id = gm.profile_id
  where g.church_id is not null
    and p.church_id is not null
    and g.church_id <> p.church_id

  union all

  select
    'manual_review',
    'people_primary_profile_church_mismatch',
    count(*)::bigint
  from public.people pe
  join public.profiles p on p.id = pe.primary_profile_id
  where pe.church_id is not null
    and p.church_id is not null
    and pe.church_id <> p.church_id

  union all

  select
    'manual_review',
    'member_profiles_profile_person_mismatch',
    count(*)::bigint
  from public.member_profiles mp
  join public.profiles p on p.id = mp.profile_id
  where p.person_id is not null
    and mp.person_id is not null
    and p.person_id <> mp.person_id
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
