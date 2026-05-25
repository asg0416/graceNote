-- Phase 3 current season plan sync:
-- After editing the current live grouping, rebuild the applied season plan rows
-- from the live groups/memberships so season records stay aligned.

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
    leader_person_id
  )
  select
    p_season_id,
    g.id,
    g.name,
    g.color_hex,
    row_number() over (order by lower(g.name), g.created_at, g.id)::integer - 1,
    (
      select lm.person_id
      from public.memberships lm
      where lm.church_id = v_season.church_id
        and lm.department_id = v_season.department_id
        and lm.group_id = g.id
        and lm.status = 'active'
        and lm.role = 'leader'
      order by lm.updated_at desc nulls last, lm.starts_at desc nulls last, lm.id
      limit 1
    )
  from public.groups g
  where g.church_id = v_season.church_id
    and g.department_id = v_season.department_id
    and g.is_active is not false
  order by lower(g.name), g.created_at, g.id;

  insert into public.regrouping_plan_assignments (
    season_id,
    plan_group_id,
    person_id,
    role_in_group,
    sort_order,
    source_membership_id,
    source_member_directory_id
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
      coalesce(p.display_name, md.full_name, '') as display_name
    from canonical_memberships cm
    left join public.regrouping_plan_groups rpg
      on rpg.season_id = p_season_id
     and rpg.source_group_id = cm.group_id
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
    mapped.legacy_member_directory_id
  from mapped_memberships mapped
  where mapped.person_id is not null
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
