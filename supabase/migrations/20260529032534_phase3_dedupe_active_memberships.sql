-- Active memberships allow one person to belong to multiple groups in the same
-- department, but the same person/group row must not be active more than once.
-- This cleans up historical duplicates from the legacy -> person transition and
-- adds guardrails so regrouping/member writes cannot recreate them.

set check_function_bodies = off;

with ranked_active as (
  select
    m.id,
    row_number() over (
      partition by m.church_id, m.department_id, m.person_id, m.group_id
      order by
        case
          when md.is_active is not false
           and (
             (m.group_id is null and nullif(btrim(coalesce(md.group_name, '')), '') is null)
             or g.name = md.group_name
           )
            then 0
          when md.is_active is not false then 1
          else 2
        end,
        m.updated_at desc nulls last,
        m.starts_at desc nulls last,
        m.id
    ) as rn
  from public.memberships m
  left join public.member_directory md on md.id = m.legacy_member_directory_id
  left join public.groups g on g.id = m.group_id
  where m.status = 'active'
)
update public.memberships m
set status = 'ended',
    ends_at = least(coalesce(m.ends_at, now()), now()),
    updated_at = now()
from ranked_active ranked
where ranked.id = m.id
  and ranked.rn > 1;

create unique index if not exists memberships_active_person_group_unique
on public.memberships (church_id, department_id, person_id, group_id)
where status = 'active' and group_id is not null;

create unique index if not exists memberships_active_person_unassigned_unique
on public.memberships (church_id, department_id, person_id)
where status = 'active' and group_id is null;
