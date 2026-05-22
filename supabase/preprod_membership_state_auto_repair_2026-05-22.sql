-- Pre-production membership state automatic repair for GraceNote person-structure rollout.
-- Mutating. Run only on dev/staging/prod clone after reading the matching audit output.
--
-- Deterministic repairs only:
-- - A membership cannot remain active when its legacy directory row is inactive.
-- - A membership cannot remain active when its legacy group_member row is inactive.
-- - A membership cannot remain active when its group or department is inactive.
--
-- This does not merge people, reactivate groups/departments, or infer new groups.

begin;

drop table if exists pg_temp._membership_state_repair_counts;

create temp table _membership_state_repair_counts (
  repair_type text primary key,
  row_count bigint not null
) on commit drop;

with repaired as (
  update public.memberships m
  set status = 'inactive',
      ends_at = coalesce(m.ends_at, md.left_at, now()),
      updated_at = now()
  from public.member_directory md
  where m.legacy_member_directory_id = md.id
    and m.status = 'active'
    and md.is_active = false
  returning m.id
)
insert into _membership_state_repair_counts
select 'inactive_directory_active_membership_end', count(*)::bigint
from repaired;

with repaired as (
  update public.memberships m
  set status = 'inactive',
      ends_at = coalesce(m.ends_at, now()),
      updated_at = now()
  from public.group_members gm
  where m.legacy_group_member_id = gm.id
    and m.status = 'active'
    and gm.is_active = false
  returning m.id
)
insert into _membership_state_repair_counts
select 'inactive_group_member_active_membership_end', count(*)::bigint
from repaired;

with repaired as (
  update public.memberships m
  set status = 'inactive',
      ends_at = coalesce(m.ends_at, now()),
      updated_at = now()
  from public.groups g
  where m.group_id = g.id
    and m.status = 'active'
    and coalesce(g.is_active, true) = false
  returning m.id
)
insert into _membership_state_repair_counts
select 'inactive_group_active_membership_end', count(*)::bigint
from repaired;

with repaired as (
  update public.memberships m
  set status = 'inactive',
      ends_at = coalesce(m.ends_at, now()),
      updated_at = now()
  from public.departments d
  where m.department_id = d.id
    and m.status = 'active'
    and coalesce(d.is_active, true) = false
  returning m.id
)
insert into _membership_state_repair_counts
select 'inactive_department_active_membership_end', count(*)::bigint
from repaired;

select repair_type, row_count
from _membership_state_repair_counts
order by repair_type;

commit;
