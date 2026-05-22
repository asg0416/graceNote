-- Pre-production identity link candidate details.
-- Read-only. Details are intentionally limited to names/emails/church/department
-- so the output can be used for rollout review without exposing secrets.

with auth_missing_profile as (
  select
    'auth_user_missing_profile' as issue_type,
    null::uuid as church_id,
    u.id as auth_user_id,
    null::uuid as profile_id,
    coalesce(u.email, '') as email,
    jsonb_build_object(
      'auth_user_id', u.id,
      'email', u.email,
      'created_at', u.created_at
    ) as details
  from auth.users u
  left join public.profiles p on p.id = u.id
  where p.id is null
),
profile_without_auth as (
  select
    'profile_without_auth_user' as issue_type,
    p.church_id,
    null::uuid as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, '') as email,
    jsonb_build_object(
      'profile_id', p.id,
      'email', p.email,
      'full_name', p.full_name,
      'church_id', p.church_id,
      'is_onboarding_complete', p.is_onboarding_complete
    ) as details
  from public.profiles p
  left join auth.users u on u.id = p.id
  where u.id is null
),
email_id_diff_target_missing as (
  select
    'profile_email_matches_auth_but_id_diff_target_missing' as issue_type,
    p.church_id,
    u.id as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, u.email, '') as email,
    jsonb_build_object(
      'repair_hint', 'copy profile row to auth user id, then move same-church references only',
      'auth_user_id', u.id,
      'source_profile_id', p.id,
      'email', p.email,
      'full_name', p.full_name,
      'church_id', p.church_id,
      'same_church_directory_refs', (
        select count(*)
        from public.member_directory md
        where md.profile_id = p.id
          and md.church_id = p.church_id
      ),
      'cross_church_directory_refs', (
        select count(*)
        from public.member_directory md
        where md.profile_id = p.id
          and md.church_id is distinct from p.church_id
      )
    ) as details
  from public.profiles p
  join auth.users u on lower(u.email) = lower(p.email)
  left join public.profiles target_profile on target_profile.id = u.id
  where p.email is not null
    and p.id <> u.id
    and target_profile.id is null
),
email_id_diff_target_exists as (
  select
    'profile_email_matches_auth_but_id_diff_target_exists' as issue_type,
    p.church_id,
    u.id as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, u.email, '') as email,
    jsonb_build_object(
      'review_hint', 'auth id already has a profile; do not auto-merge',
      'auth_user_id', u.id,
      'source_profile_id', p.id,
      'target_profile_name', target_profile.full_name,
      'source_profile_name', p.full_name,
      'email', p.email
    ) as details
  from public.profiles p
  join auth.users u on lower(u.email) = lower(p.email)
  join public.profiles target_profile on target_profile.id = u.id
  where p.email is not null
    and p.id <> u.id
),
profile_auth_email_diff as (
  select
    'profile_email_differs_from_auth_email' as issue_type,
    p.church_id,
    u.id as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, u.email, '') as email,
    jsonb_build_object(
      'auth_email', u.email,
      'profile_email', p.email,
      'full_name', p.full_name
    ) as details
  from public.profiles p
  join auth.users u on u.id = p.id
  where nullif(lower(coalesce(p.email, '')), '') is not null
    and nullif(lower(coalesce(u.email, '')), '') is not null
    and lower(p.email) <> lower(u.email)
),
same_email_profiles as (
  select
    'same_email_multiple_profiles' as issue_type,
    null::uuid as church_id,
    null::uuid as auth_user_id,
    null::uuid as profile_id,
    lower(p.email) as email,
    jsonb_agg(
      jsonb_build_object(
        'profile_id', p.id,
        'church_id', p.church_id,
        'full_name', p.full_name,
        'is_onboarding_complete', p.is_onboarding_complete
      )
      order by p.full_name, p.id
    ) as details
  from public.profiles p
  where nullif(lower(coalesce(p.email, '')), '') is not null
  group by lower(p.email)
  having count(*) > 1
),
directory_profile_church_mismatch as (
  select
    'member_directory_profile_church_mismatch' as issue_type,
    md.church_id,
    null::uuid as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, '') as email,
    jsonb_build_object(
      'member_directory_id', md.id,
      'member_name', md.full_name,
      'directory_church_id', md.church_id,
      'profile_id', p.id,
      'profile_name', p.full_name,
      'profile_church_id', p.church_id
    ) as details
  from public.member_directory md
  join public.profiles p on p.id = md.profile_id
  where md.church_id is not null
    and p.church_id is not null
    and md.church_id <> p.church_id
),
member_profile_church_mismatch as (
  select
    'member_profiles_profile_church_mismatch' as issue_type,
    md.church_id,
    null::uuid as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, '') as email,
    jsonb_build_object(
      'member_profile_id', mp.id,
      'member_directory_id', md.id,
      'member_name', md.full_name,
      'directory_church_id', md.church_id,
      'profile_id', p.id,
      'profile_name', p.full_name,
      'profile_church_id', p.church_id
    ) as details
  from public.member_profiles mp
  join public.member_directory md on md.id = mp.member_directory_id
  join public.profiles p on p.id = mp.profile_id
  where md.church_id is not null
    and p.church_id is not null
    and md.church_id <> p.church_id
),
group_member_church_mismatch as (
  select
    'group_members_profile_church_mismatch' as issue_type,
    g.church_id,
    null::uuid as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, '') as email,
    jsonb_build_object(
      'group_member_id', gm.id,
      'group_id', g.id,
      'group_name', g.name,
      'group_church_id', g.church_id,
      'profile_id', p.id,
      'profile_name', p.full_name,
      'profile_church_id', p.church_id
    ) as details
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  join public.profiles p on p.id = gm.profile_id
  where g.church_id is not null
    and p.church_id is not null
    and g.church_id <> p.church_id
),
people_primary_profile_church_mismatch as (
  select
    'people_primary_profile_church_mismatch' as issue_type,
    pe.church_id,
    null::uuid as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, '') as email,
    jsonb_build_object(
      'person_id', pe.id,
      'display_name', pe.display_name,
      'person_church_id', pe.church_id,
      'primary_profile_id', p.id,
      'profile_name', p.full_name,
      'profile_church_id', p.church_id
    ) as details
  from public.people pe
  join public.profiles p on p.id = pe.primary_profile_id
  where pe.church_id is not null
    and p.church_id is not null
    and pe.church_id <> p.church_id
),
member_profile_person_mismatch as (
  select
    'member_profiles_profile_person_mismatch' as issue_type,
    md.church_id,
    null::uuid as auth_user_id,
    p.id as profile_id,
    coalesce(p.email, '') as email,
    jsonb_build_object(
      'member_profile_id', mp.id,
      'member_directory_id', mp.member_directory_id,
      'member_name', mp.full_name,
      'member_profile_person_id', mp.person_id,
      'profile_id', p.id,
      'profile_name', p.full_name,
      'profile_person_id', p.person_id
    ) as details
  from public.member_profiles mp
  left join public.member_directory md on md.id = mp.member_directory_id
  join public.profiles p on p.id = mp.profile_id
  where p.person_id is not null
    and mp.person_id is not null
    and p.person_id <> mp.person_id
),
all_candidates as (
  select * from auth_missing_profile
  union all select * from profile_without_auth
  union all select * from email_id_diff_target_missing
  union all select * from email_id_diff_target_exists
  union all select * from profile_auth_email_diff
  union all select * from same_email_profiles
  union all select * from directory_profile_church_mismatch
  union all select * from member_profile_church_mismatch
  union all select * from group_member_church_mismatch
  union all select * from people_primary_profile_church_mismatch
  union all select * from member_profile_person_mismatch
)
select
  c.issue_type,
  ch.name as church_name,
  c.church_id,
  c.auth_user_id,
  c.profile_id,
  c.email,
  c.details
from all_candidates c
left join public.churches ch on ch.id = c.church_id
order by c.issue_type, ch.name nulls last, c.email, c.profile_id nulls last;
