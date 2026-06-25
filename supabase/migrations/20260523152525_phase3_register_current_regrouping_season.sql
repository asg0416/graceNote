-- Phase 3 regrouping season registration:
-- Promote the current live grouping into an applied season record without
-- rewriting live groups, memberships, member_directory, or group_members.

set check_function_bodies = off;

create or replace function public.register_current_regrouping_season(
  p_church_id uuid,
  p_department_id uuid,
  p_title text,
  p_effective_week_date date,
  p_end_week_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season_id uuid;
  v_title text := nullif(btrim(p_title), '');
  v_group_count integer := 0;
  v_assignment_count integer := 0;
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if not exists (
    select 1
    from public.departments d
    where d.id = p_department_id
      and d.church_id = p_church_id
  ) then
    raise exception 'department does not belong to church.';
  end if;

  if not (
    public.check_is_master()
    or public.is_admin_approved(p_church_id)
  ) then
    raise exception 'not allowed to register regrouping season.';
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

  if exists (
    select 1
    from public.regrouping_seasons s
    where s.church_id = p_church_id
      and s.department_id = p_department_id
      and s.status = 'applied'
      and s.effective_week_date <= p_effective_week_date
      and (s.end_week_date is null or s.end_week_date >= p_effective_week_date)
  ) then
    raise exception 'an applied regrouping season already covers this week.';
  end if;

  select count(*)
  into v_group_count
  from public.groups g
  where g.church_id = p_church_id
    and g.department_id = p_department_id
    and g.is_active is not false;

  select count(*)
  into v_assignment_count
  from public.memberships m
  where m.church_id = p_church_id
    and m.department_id = p_department_id
    and m.status = 'active';

  if v_group_count = 0 and v_assignment_count = 0 then
    raise exception 'there is no active grouping to register.';
  end if;

  insert into public.regrouping_seasons (
    church_id,
    department_id,
    title,
    status,
    effective_week_date,
    end_week_date,
    created_by,
    applied_by,
    applied_at
  )
  values (
    p_church_id,
    p_department_id,
    v_title,
    'applied',
    p_effective_week_date,
    p_end_week_date,
    auth.uid(),
    auth.uid(),
    now()
  )
  returning id into v_season_id;

  insert into public.regrouping_plan_groups (
    season_id,
    source_group_id,
    name,
    color_hex,
    sort_order,
    leader_person_id
  )
  select
    v_season_id,
    g.id,
    g.name,
    g.color_hex,
    row_number() over (order by lower(g.name), g.created_at, g.id)::integer - 1,
    (
      select lm.person_id
      from public.memberships lm
      where lm.church_id = p_church_id
        and lm.department_id = p_department_id
        and lm.group_id = g.id
        and lm.status = 'active'
        and lm.role = 'leader'
      order by lm.updated_at desc nulls last, lm.starts_at desc nulls last, lm.id
      limit 1
    )
  from public.groups g
  where g.church_id = p_church_id
    and g.department_id = p_department_id
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
    where m.church_id = p_church_id
      and m.department_id = p_department_id
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
      on rpg.season_id = v_season_id
     and rpg.source_group_id = cm.group_id
    left join public.people p on p.id = cm.person_id
    left join public.member_directory md on md.id = cm.legacy_member_directory_id
  )
  select
    v_season_id,
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
  where id = v_season_id;

  return v_season_id;
end;
$$;

create or replace function public.register_current_regrouping_season(
  p_church_id uuid,
  p_department_id uuid,
  p_title text,
  p_effective_week_date date
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.register_current_regrouping_season(
    p_church_id,
    p_department_id,
    p_title,
    p_effective_week_date,
    null::date
  );
$$;

grant execute on function public.register_current_regrouping_season(
  uuid,
  uuid,
  text,
  date,
  date
) to authenticated, service_role;

grant execute on function public.register_current_regrouping_season(
  uuid,
  uuid,
  text,
  date
) to authenticated, service_role;
