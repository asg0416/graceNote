-- Narrow assignment syncing to rows that belong to default-period groups.
-- This keeps custom-period groups and their members independent from season shell edits.

set check_function_bodies = off;

create or replace function public.update_regrouping_season(
  p_season_id uuid,
  p_title text,
  p_effective_week_date date,
  p_end_week_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_title text := nullif(btrim(p_title), '');
  v_old_effective_week_date date;
  v_old_end_week_date date;
  v_active_plan_group_count integer := 0;
  v_default_plan_group_count integer := 0;
  v_default_plan_group_start date;
  v_default_plan_group_end date;
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
    raise exception 'not allowed to update regrouping season.';
  end if;

  if v_season.status not in ('draft', 'ready', 'applied') then
    raise exception 'only draft, ready, or applied regrouping season periods are editable.';
  end if;

  if v_title is null then
    raise exception 'title is required.';
  end if;

  if p_effective_week_date is null then
    raise exception 'effective_week_date is required.';
  end if;

  if extract(dow from p_effective_week_date)::integer <> 0 then
    raise exception 'effective_week_date must be a Sunday.';
  end if;

  if p_end_week_date is not null and extract(dow from p_end_week_date)::integer <> 0 then
    raise exception 'end_week_date must be a Sunday.';
  end if;

  if p_end_week_date is not null and p_end_week_date < p_effective_week_date then
    raise exception 'end_week_date must be on or after effective_week_date.';
  end if;

  v_old_effective_week_date := v_season.effective_week_date;
  v_old_end_week_date := v_season.end_week_date;

  select count(*)::integer
  into v_active_plan_group_count
  from public.regrouping_plan_groups
  where season_id = p_season_id
    and coalesce(plan_status, 'active') <> 'ended';

  select starts_week_date, ends_week_date, count(*)::integer
  into v_default_plan_group_start, v_default_plan_group_end, v_default_plan_group_count
  from public.regrouping_plan_groups
  where season_id = p_season_id
    and coalesce(plan_status, 'active') <> 'ended'
  group by starts_week_date, ends_week_date
  order by count(*) desc
  limit 1;

  if v_default_plan_group_count < greatest(2, ceil(v_active_plan_group_count::numeric * 0.6)::integer) then
    v_default_plan_group_start := null;
    v_default_plan_group_end := null;
  end if;

  update public.regrouping_plan_groups rpg
  set starts_week_date = p_effective_week_date,
      ends_week_date = p_end_week_date,
      updated_at = now()
  where rpg.season_id = p_season_id
    and (
      (
        rpg.starts_week_date is not distinct from v_old_effective_week_date
        and rpg.ends_week_date is not distinct from v_old_end_week_date
      )
      or (
        v_default_plan_group_start is not null
        and rpg.starts_week_date is not distinct from v_default_plan_group_start
        and rpg.ends_week_date is not distinct from v_default_plan_group_end
      )
    );

  update public.regrouping_plan_assignments rpa
  set starts_week_date = p_effective_week_date,
      ends_week_date = p_end_week_date,
      updated_at = now()
  where rpa.season_id = p_season_id
    and (
      (
        rpa.starts_week_date is not distinct from v_old_effective_week_date
        and rpa.ends_week_date is not distinct from v_old_end_week_date
      )
      or (
        v_default_plan_group_start is not null
        and rpa.starts_week_date is not distinct from v_default_plan_group_start
        and rpa.ends_week_date is not distinct from v_default_plan_group_end
      )
    )
    and (
      rpa.plan_group_id is null
      or exists (
        select 1
        from public.regrouping_plan_groups updated_rpg
        where updated_rpg.id = rpa.plan_group_id
          and updated_rpg.season_id = p_season_id
          and updated_rpg.starts_week_date is not distinct from p_effective_week_date
          and updated_rpg.ends_week_date is not distinct from p_end_week_date
      )
    );

  update public.regrouping_seasons
  set title = v_title,
      effective_week_date = p_effective_week_date,
      end_week_date = p_end_week_date,
      updated_at = now()
  where id = p_season_id;
end;
$$;

create or replace function public.update_regrouping_season(
  p_season_id uuid,
  p_title text,
  p_effective_week_date date
)
returns void
language sql
security definer
set search_path = public
as $$
  select public.update_regrouping_season(
    p_season_id,
    p_title,
    p_effective_week_date,
    null::date
  );
$$;

grant execute on function public.update_regrouping_season(uuid, text, date, date) to authenticated, service_role;
grant execute on function public.update_regrouping_season(uuid, text, date) to authenticated, service_role;
