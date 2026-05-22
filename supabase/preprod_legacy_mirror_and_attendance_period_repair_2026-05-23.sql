-- Pre-production legacy mirror and attendance period repair.
-- Mutating. Run only on dev/staging/prod clone, or during an approved
-- production maintenance window after reviewing the matching gate output.
--
-- Deterministic repairs only:
-- - If a person-structure membership is inactive/ended, the legacy
--   group_members mirror row must not remain active.
-- - If attendance exists before a group's active_from, the group active period
--   is widened to include the earliest recorded attendance week.

begin;

drop table if exists pg_temp._legacy_mirror_repair_counts;

create temp table _legacy_mirror_repair_counts (
  repair_type text primary key,
  row_count bigint not null
) on commit drop;

with repaired as (
  update public.group_members gm
  set is_active = false
  from public.memberships m
  where m.legacy_group_member_id = gm.id
    and coalesce(gm.is_active, true) = true
    and m.status in ('inactive', 'ended')
  returning gm.id
)
insert into _legacy_mirror_repair_counts
select 'legacy_group_member_deactivate_from_membership_state', count(*)::bigint
from repaired;

with first_attendance_week as (
  select
    g.id as group_id,
    min(w.week_date)::date as first_week_date
  from public.attendance a
  join public.weeks w on w.id = a.week_id
  join public.groups g on g.id = coalesce(a.recorded_group_id, a.group_id)
  where g.active_from is not null
    and g.active_from > w.week_date
  group by g.id
),
repaired as (
  update public.groups g
  set active_from = f.first_week_date
  from first_attendance_week f
  where g.id = f.group_id
    and g.active_from > f.first_week_date
  returning g.id
)
insert into _legacy_mirror_repair_counts
select 'group_active_from_widened_to_first_attendance_week', count(*)::bigint
from repaired;

select repair_type, row_count
from _legacy_mirror_repair_counts
order by repair_type;

commit;
