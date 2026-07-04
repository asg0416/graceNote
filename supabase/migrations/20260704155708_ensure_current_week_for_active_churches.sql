-- Pre-create the current operational week for every church that has at least
-- one department. This prevents Sunday leader/admin screens from rendering as
-- empty simply because no user has created the week row yet.

set check_function_bodies = off;

create or replace function public.ensure_current_week_exists_for_active_churches(
  p_week_date date default null
)
returns table(
  church_id uuid,
  week_id uuid,
  week_date date,
  created boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_date date := coalesce(
    public.phase3_week_start(p_week_date),
    public.phase3_week_start((now() at time zone 'Asia/Seoul')::date)
  );
begin
  if not (
    session_user in ('postgres', 'service_role', 'supabase_admin')
    or coalesce(auth.role(), '') = 'service_role'
    or public.check_is_master()
  ) then
    raise exception 'not allowed to ensure weekly rows for active churches.';
  end if;

  return query
  with target_churches as (
    select distinct d.church_id
    from public.departments d
    join public.churches c
      on c.id = d.church_id
    where d.church_id is not null
  ),
  existing as (
    select w.church_id
    from public.weeks w
    join target_churches tc
      on tc.church_id = w.church_id
    where w.week_date = v_week_date
  ),
  upserted as (
    insert into public.weeks (
      church_id,
      week_date,
      is_active
    )
    select
      tc.church_id,
      v_week_date,
      true
    from target_churches tc
    on conflict (church_id, week_date) do update
    set is_active = true
    returning
      public.weeks.church_id,
      public.weeks.id,
      public.weeks.week_date
  )
  select
    upserted.church_id,
    upserted.id,
    upserted.week_date,
    not exists (
      select 1
      from existing
      where existing.church_id = upserted.church_id
    ) as created
  from upserted
  order by upserted.week_date, upserted.church_id;
end;
$$;

revoke execute on function public.ensure_current_week_exists_for_active_churches(date)
from public, anon, authenticated;

grant execute on function public.ensure_current_week_exists_for_active_churches(date)
to service_role;
