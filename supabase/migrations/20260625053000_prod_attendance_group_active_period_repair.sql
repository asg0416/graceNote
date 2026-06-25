-- Align group active periods with existing attendance rows.
-- Some prod-clone data had attendance recorded on the Sunday before the
-- group's active_from date. Historical attendance must remain visible for the
-- week where it was actually submitted.

with attendance_group_bounds as (
  select
    coalesce(a.recorded_group_id, a.group_id) as group_id,
    min(w.week_date)::date as first_attendance_week
  from public.attendance a
  join public.weeks w
    on w.id = a.week_id
  where coalesce(a.recorded_group_id, a.group_id) is not null
  group by coalesce(a.recorded_group_id, a.group_id)
)
update public.groups g
set active_from = bounds.first_attendance_week
from attendance_group_bounds bounds
where bounds.group_id = g.id
  and bounds.first_attendance_week is not null
  and g.active_from is not null
  and g.active_from > bounds.first_attendance_week;
