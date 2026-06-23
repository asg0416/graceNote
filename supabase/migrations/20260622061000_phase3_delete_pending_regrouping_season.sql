-- Delete only future pending regrouping season plans.
-- This removes draft/ready planning rows only and never touches live groups,
-- memberships, people, attendance, or prayer records.

create or replace function public.delete_pending_regrouping_season(
  p_season_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
begin
  if p_season_id is null then
    raise exception 'season_id is required.';
  end if;

  select *
    into v_season
    from public.regrouping_seasons
   where id = p_season_id
   for update;

  if not found then
    raise exception 'regrouping season not found.';
  end if;

  if not (
    public.check_is_master()
    or public.is_admin_approved(v_season.church_id)
  ) then
    raise exception 'not allowed to delete regrouping season.';
  end if;

  if v_season.status not in ('draft', 'ready') then
    raise exception 'only pending regrouping seasons can be deleted.';
  end if;

  if v_season.effective_week_date <= current_date then
    raise exception 'only future regrouping seasons can be deleted.';
  end if;

  delete from public.regrouping_plan_assignments
   where season_id = p_season_id;

  delete from public.regrouping_plan_groups
   where season_id = p_season_id;

  delete from public.regrouping_seasons
   where id = p_season_id;

  return true;
end;
$$;

grant execute on function public.delete_pending_regrouping_season(uuid) to authenticated, service_role;
