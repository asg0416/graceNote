-- Fix PL/pgSQL name collisions between RETURNS TABLE output columns and
-- weeks/departments column references inside the current-week bootstrap RPC.

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
#variable_conflict use_column
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
    select distinct d.church_id as target_church_id
    from public.departments d
    join public.churches c
      on c.id = d.church_id
    where d.church_id is not null
  ),
  existing as (
    select w.church_id as existing_church_id
    from public.weeks w
    join target_churches tc
      on tc.target_church_id = w.church_id
    where w.week_date = v_week_date
  ),
  upserted as (
    insert into public.weeks (
      church_id,
      week_date,
      is_active
    )
    select
      tc.target_church_id,
      v_week_date,
      true
    from target_churches tc
    on conflict on constraint weeks_church_id_week_date_key do update
    set is_active = true
    returning
      public.weeks.church_id as upserted_church_id,
      public.weeks.id as upserted_week_id,
      public.weeks.week_date as upserted_week_date
  )
  select
    upserted.upserted_church_id,
    upserted.upserted_week_id,
    upserted.upserted_week_date,
    not exists (
      select 1
      from existing
      where existing.existing_church_id = upserted.upserted_church_id
    ) as created
  from upserted
  order by upserted.upserted_week_date, upserted.upserted_church_id;
end;
$$;

revoke execute on function public.ensure_current_week_exists_for_active_churches(date)
from public, anon, authenticated;

grant execute on function public.ensure_current_week_exists_for_active_churches(date)
to service_role;
