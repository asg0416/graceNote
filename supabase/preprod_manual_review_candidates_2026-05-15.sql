-- Pre-production manual review candidates for GraceNote person-structure rollout.
-- Read-only. This query lists identity/family/phone situations that should not
-- be auto-merged during rollout.

with same_church_people_phone as (
  select
    'same_church_duplicate_people_phone' as issue_type,
    p.church_id,
    p.normalized_phone as phone_key,
    jsonb_agg(
      jsonb_build_object(
        'person_id', p.id,
        'display_name', p.display_name,
        'normalized_phone', p.normalized_phone,
        'primary_profile_id', p.primary_profile_id
      )
      order by p.display_name, p.id
    ) as details
  from public.people p
  where p.normalized_phone is not null
  group by p.church_id, p.normalized_phone
  having count(*) > 1
),
same_church_directory_phone as (
  select
    'same_church_active_directory_duplicate_phone' as issue_type,
    md.church_id,
    regexp_replace(coalesce(md.phone, ''), '[^0-9]', '', 'g') as phone_key,
    jsonb_agg(
      jsonb_build_object(
        'member_directory_id', md.id,
        'person_id', md.person_id,
        'profile_id', md.profile_id,
        'full_name', md.full_name,
        'phone', md.phone,
        'department_id', md.department_id,
        'group_name', md.group_name
      )
      order by md.full_name, md.id
    ) as details
  from public.member_directory md
  where coalesce(md.is_active, true) = true
    and nullif(regexp_replace(coalesce(md.phone, ''), '[^0-9]', '', 'g'), '') is not null
  group by md.church_id, regexp_replace(coalesce(md.phone, ''), '[^0-9]', '', 'g')
  having count(distinct coalesce(md.person_id, md.profile_id, md.id)) > 1
),
same_church_same_name_people as (
  select
    'same_church_same_name_multi_people' as issue_type,
    p.church_id,
    btrim(p.display_name) as phone_key,
    jsonb_agg(
      jsonb_build_object(
        'person_id', p.id,
        'display_name', p.display_name,
        'normalized_phone', p.normalized_phone,
        'primary_profile_id', p.primary_profile_id
      )
      order by p.normalized_phone nulls last, p.id
    ) as details
  from public.people p
  where nullif(btrim(p.display_name), '') is not null
  group by p.church_id, btrim(p.display_name)
  having count(*) > 1
),
cross_church_people_phone as (
  select
    'cross_church_same_phone_people' as issue_type,
    null::uuid as church_id,
    p.normalized_phone as phone_key,
    jsonb_agg(
      jsonb_build_object(
        'church_id', p.church_id,
        'person_id', p.id,
        'display_name', p.display_name,
        'normalized_phone', p.normalized_phone
      )
      order by p.church_id, p.display_name, p.id
    ) as details
  from public.people p
  where p.normalized_phone is not null
  group by p.normalized_phone
  having count(distinct p.church_id) > 1
),
profile_church_mismatch as (
  select
    'member_directory_profile_church_mismatch' as issue_type,
    md.church_id,
    md.id::text as phone_key,
    jsonb_build_array(
      jsonb_build_object(
        'member_directory_id', md.id,
        'full_name', md.full_name,
        'phone', md.phone,
        'member_directory_church_id', md.church_id,
        'profile_id', pr.id,
        'profile_church_id', pr.church_id,
        'profile_name', pr.full_name
      )
    ) as details
  from public.member_directory md
  join public.profiles pr on pr.id = md.profile_id
  where md.church_id is not null
    and pr.church_id is not null
    and md.church_id <> pr.church_id
),
all_candidates as (
  select * from same_church_people_phone
  union all
  select * from same_church_directory_phone
  union all
  select * from same_church_same_name_people
  union all
  select * from cross_church_people_phone
  union all
  select * from profile_church_mismatch
)
select
  c.issue_type,
  ch.name as church_name,
  c.church_id,
  c.phone_key,
  jsonb_array_length(c.details) as candidate_count,
  c.details
from all_candidates c
left join public.churches ch on ch.id = c.church_id
order by c.issue_type, ch.name nulls last, c.phone_key;
