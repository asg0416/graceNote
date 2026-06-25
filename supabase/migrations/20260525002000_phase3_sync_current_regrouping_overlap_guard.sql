-- Guard current season plan sync against live groups/memberships whose active
-- period starts after the season ends. Those rows do not overlap the selected
-- season and would violate plan period order constraints.

set check_function_bodies = off;

create or replace function public.sync_current_regrouping_season_plan_from_live(
  p_season_id uuid
)
returns table(plan_group_count integer, assignment_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_season_end_date date;
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
    raise exception 'not allowed to sync regrouping season.';
  end if;

  if v_season.status <> 'applied'
     or not public.phase3_regrouping_season_is_current(
       v_season.effective_week_date,
       v_season.end_week_date
     ) then
    raise exception 'only current applied regrouping seasons can sync live plan rows.';
  end if;

  v_season_end_date := coalesce(v_season.end_week_date + 6, '9999-12-31'::date);

  delete from public.regrouping_plan_assignments
  where season_id = p_season_id;

  delete from public.regrouping_plan_groups
  where season_id = p_season_id;

  insert into public.regrouping_plan_groups (
    season_id,
    source_group_id,
    name,
    color_hex,
    sort_order,
    leader_person_id,
    starts_week_date,
    ends_week_date,
    plan_status
  )
  with eligible_groups as (
    select
      g.*,
      greatest(
        coalesce(public.phase3_week_start(g.active_from), v_season.effective_week_date),
        v_season.effective_week_date
      ) as plan_starts_week,
      case
        when g.is_active is false and g.ended_at is not null
          then greatest(public.phase3_week_start(g.ended_at::date), v_season.effective_week_date)
        else v_season.end_week_date
      end as plan_ends_week,
      case when g.is_active is false then 'ended' else 'active' end as plan_status
    from public.groups g
    where g.church_id = v_season.church_id
      and g.department_id = v_season.department_id
      and (
        g.is_active is not false
        or (
          g.ended_at is not null
          and g.ended_at::date >= v_season.effective_week_date
          and g.ended_at::date <= v_season_end_date
        )
      )
  )
  select
    p_season_id,
    eg.id,
    eg.name,
    eg.color_hex,
    row_number() over (order by case when eg.plan_status = 'ended' then 1 else 0 end, lower(eg.name), eg.created_at, eg.id)::integer - 1,
    (
      select lm.person_id
      from public.memberships lm
      where lm.church_id = v_season.church_id
        and lm.department_id = v_season.department_id
        and lm.group_id = eg.id
        and lm.status = 'active'
        and lm.role = 'leader'
      order by lm.updated_at desc nulls last, lm.starts_at desc nulls last, lm.id
      limit 1
    ),
    eg.plan_starts_week,
    eg.plan_ends_week,
    eg.plan_status
  from eligible_groups eg
  where eg.plan_starts_week <= coalesce(eg.plan_ends_week, eg.plan_starts_week)
  order by case when eg.plan_status = 'ended' then 1 else 0 end, lower(eg.name), eg.created_at, eg.id;

  insert into public.regrouping_plan_assignments (
    season_id,
    plan_group_id,
    person_id,
    role_in_group,
    sort_order,
    source_membership_id,
    source_member_directory_id,
    starts_week_date,
    ends_week_date
  )
  with ranked_memberships as (
    select
      m.*,
      row_number() over (
        partition by m.person_id, m.group_id
        order by m.updated_at desc nulls last, m.starts_at desc nulls last, m.id
      ) as duplicate_rank
    from public.memberships m
    where m.church_id = v_season.church_id
      and m.department_id = v_season.department_id
      and m.status = 'active'
  ),
  canonical_memberships as (
    select *
    from ranked_memberships
    where duplicate_rank = 1
  ),
  mapped_memberships as (
    select
      cm.id as membership_id,
      cm.person_id,
      cm.legacy_member_directory_id,
      case
        when cm.role = 'leader' then 'leader'
        else 'member'
      end as plan_role,
      rpg.id as plan_group_id,
      coalesce(p.display_name, md.full_name, '') as display_name,
      greatest(
        coalesce(public.phase3_week_start(cm.starts_at::date), v_season.effective_week_date),
        v_season.effective_week_date
      ) as starts_week_date
    from canonical_memberships cm
    join public.regrouping_plan_groups rpg
      on rpg.season_id = p_season_id
     and rpg.source_group_id = cm.group_id
     and rpg.plan_status = 'active'
    left join public.people p on p.id = cm.person_id
    left join public.member_directory md on md.id = cm.legacy_member_directory_id
  )
  select
    p_season_id,
    mapped.plan_group_id,
    mapped.person_id,
    mapped.plan_role,
    row_number() over (
      partition by mapped.plan_group_id
      order by case when mapped.plan_role = 'leader' then 0 else 1 end,
               lower(mapped.display_name),
               mapped.person_id
    )::integer - 1,
    mapped.membership_id,
    mapped.legacy_member_directory_id,
    mapped.starts_week_date,
    v_season.end_week_date
  from mapped_memberships mapped
  where mapped.person_id is not null
    and mapped.starts_week_date <= coalesce(v_season.end_week_date, mapped.starts_week_date)
  on conflict do nothing;

  update public.regrouping_seasons
  set updated_at = now()
  where id = p_season_id;

  return query
  select
    (select count(*)::integer from public.regrouping_plan_groups where season_id = p_season_id),
    (select count(*)::integer from public.regrouping_plan_assignments where season_id = p_season_id);
end;
$$;

grant execute on function public.sync_current_regrouping_season_plan_from_live(uuid) to authenticated, service_role;
