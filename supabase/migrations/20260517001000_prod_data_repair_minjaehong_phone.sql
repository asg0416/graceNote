-- Prod data repair:
-- Confirmed by operator before rollout. 민재홍's phone was copied from 임진슬.
-- Keep this repair narrow so it cannot affect similarly named people elsewhere.

with target_church as (
  select id
  from public.churches
  where name = '장전제일교회'
  limit 1
),
target_directory as (
  update public.member_directory md
  set
    phone = '01044888901'
  from target_church tc
  where md.church_id = tc.id
    and md.id = 'd778e930-2d99-4723-985a-7047ca86b1bb'::uuid
    and md.full_name = '민재홍'
    and public.phase2_normalize_phone(md.phone) = '01025612632'
  returning md.id, md.person_id
),
updated_people as (
  update public.people p
  set
    normalized_phone = '01044888901',
    updated_at = now()
  from target_directory td
  where p.id = td.person_id
  returning p.id
),
updated_member_profiles as (
  update public.member_profiles mp
  set
    phone = '01044888901',
    updated_at = now()
  from target_directory td
  where mp.member_directory_id = td.id
  returning mp.person_id
)
update public.person_identifiers pi
set
  value = '01044888901'
from target_directory td
where pi.person_id = td.person_id
  and pi.kind = 'phone'
  and pi.source_table = 'member_directory'
  and pi.source_id = td.id
  and pi.value = '01025612632';
