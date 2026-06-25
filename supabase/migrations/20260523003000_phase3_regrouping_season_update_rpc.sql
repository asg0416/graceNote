-- Phase 3 regrouping season metadata update RPC.
-- Allows admins to edit title/effective week for draft/ready seasons without
-- touching live groups or memberships.

set check_function_bodies = off;

create or replace function public.update_regrouping_season(
  p_season_id uuid,
  p_title text,
  p_effective_week_date date
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

  if v_season.status not in ('draft', 'ready') then
    raise exception 'only draft or ready regrouping seasons are editable.';
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

  update public.regrouping_seasons
  set title = v_title,
      effective_week_date = p_effective_week_date,
      updated_at = now()
  where id = p_season_id;
end;
$$;

grant execute on function public.update_regrouping_season(
  uuid,
  text,
  date
) to authenticated, service_role;
