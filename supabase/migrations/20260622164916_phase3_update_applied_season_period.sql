-- Allow applied regrouping season metadata/period correction.
-- This RPC only updates the season shell (title + period). It does not edit
-- plan groups, plan assignments, live groups, or live memberships.

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
