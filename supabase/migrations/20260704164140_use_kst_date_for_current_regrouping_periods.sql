-- Treat "today/current week" for regrouping admin operations as Korea time.
-- Supabase/Postgres current_date is UTC, so early Sunday KST can otherwise
-- still be evaluated as Saturday and reject the newly applied season.

set check_function_bodies = off;

create or replace function public.phase3_regrouping_season_is_current(
  p_effective_week_date date,
  p_end_week_date date
)
returns boolean
language sql
stable
as $$
  select p_effective_week_date <= (now() at time zone 'Asia/Seoul')::date
     and (
       p_end_week_date is null
       or (p_end_week_date + 6) >= (now() at time zone 'Asia/Seoul')::date
     );
$$;

grant execute on function public.phase3_regrouping_season_is_current(date, date)
to authenticated, service_role;

create or replace function public.update_current_regrouping_group_periods(
  p_season_id uuid,
  p_groups jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_group jsonb;
  v_source_group_id uuid;
  v_status text;
  v_current_week date := public.phase3_week_start((now() at time zone 'Asia/Seoul')::date);
  v_starts_week date;
  v_ends_week date;
  v_updated_count integer := 0;
  v_row_count integer := 0;
begin
  select *
  into v_season
  from public.regrouping_seasons
  where id = p_season_id
  for update;

  if v_season.id is null then
    raise exception 'regrouping season not found.';
  end if;

  if not (
    public.check_is_master()
    or public.is_admin_approved(v_season.church_id)
  ) then
    raise exception 'not allowed to update current regrouping group periods.';
  end if;

  if v_season.status <> 'applied'
     or not public.phase3_regrouping_season_is_current(
       v_season.effective_week_date,
       v_season.end_week_date
     ) then
    raise exception 'only current applied regrouping seasons can update live group periods.';
  end if;

  for v_group in
    select value
    from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) as g(value)
  loop
    v_source_group_id := case
      when public.phase3_is_uuid(nullif(v_group->>'source_group_id', ''))
        then nullif(v_group->>'source_group_id', '')::uuid
      else null
    end;

    if v_source_group_id is null then
      continue;
    end if;

    v_status := case
      when v_group->>'plan_status' = 'ended' then 'ended'
      else 'active'
    end;

    v_starts_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'starts_week_date', '')::date),
      v_season.effective_week_date
    );
    if v_starts_week > v_current_week then
      v_starts_week := v_current_week;
    end if;
    if v_starts_week < v_season.effective_week_date then
      v_starts_week := v_season.effective_week_date;
    end if;

    v_ends_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'ends_week_date', '')::date),
      v_season.end_week_date,
      v_current_week
    );

    if v_ends_week < v_starts_week then
      raise exception 'group end week must be on or after start week.';
    end if;

    update public.groups g
    set active_from = v_starts_week,
        is_active = (v_status = 'active'),
        ended_at = case
          when v_status = 'ended'
            then ((v_ends_week + 7)::timestamp - interval '1 second')
          else null
        end
    where g.id = v_source_group_id
      and g.church_id = v_season.church_id
      and g.department_id = v_season.department_id;

    get diagnostics v_row_count = row_count;
    v_updated_count := v_updated_count + v_row_count;
  end loop;

  return v_updated_count;
end;
$$;

grant execute on function public.update_current_regrouping_group_periods(uuid, jsonb)
to authenticated, service_role;
