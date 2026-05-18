-- Backfill group active_from from historical attendance/prayer records.
-- Some groups were created or soft-disabled during dev cleanup after they had
-- historical records. Their operating period must start at the earliest week
-- where the group actually has attendance or prayer data.

with group_history as (
  select
    coalesce(a.recorded_group_id, a.group_id) as group_id,
    min(w.week_date) as first_recorded_week
  from public.attendance a
  join public.weeks w on w.id = a.week_id
  where coalesce(a.recorded_group_id, a.group_id) is not null
  group by coalesce(a.recorded_group_id, a.group_id)

  union all

  select
    coalesce(pe.recorded_group_id, pe.group_id) as group_id,
    min(w.week_date) as first_recorded_week
  from public.prayer_entries pe
  join public.weeks w on w.id = pe.week_id
  where coalesce(pe.recorded_group_id, pe.group_id) is not null
  group by coalesce(pe.recorded_group_id, pe.group_id)
),
earliest_group_history as (
  select
    group_id,
    min(first_recorded_week) as first_recorded_week
  from group_history
  where group_id is not null
  group by group_id
)
update public.groups g
set
  active_from = case
    when g.active_from is null then e.first_recorded_week
    when e.first_recorded_week < g.active_from then e.first_recorded_week
    else g.active_from
  end
from earliest_group_history e
where e.group_id = g.id
  and (
    g.active_from is null
    or e.first_recorded_week < g.active_from
  );
