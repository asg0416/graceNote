-- Keep app-driven member moves inside the current applied season and preserve
-- the source assignment period for attendance/history calculations.

set check_function_bodies = off;

create or replace function public.move_member_directory_to_group(
  p_member_directory_id uuid,
  p_source_group_id uuid,
  p_target_group_id uuid,
  p_effective_week_date date
)
returns public.member_directory
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.member_directory%rowtype;
  v_saved public.member_directory%rowtype;
  v_source_group public.groups%rowtype;
  v_target_group public.groups%rowtype;
  v_current_season public.regrouping_seasons%rowtype;
  v_requested_week date := public.phase3_week_start(coalesce(p_effective_week_date, current_date));
  v_today_week date := public.phase3_week_start(current_date);
  v_effective_week date;
  v_effective_start timestamp with time zone;
  v_source_end timestamp with time zone;
  v_person_id uuid;
  v_target_membership_id uuid;
  v_source_plan_group_id uuid;
  v_target_plan_group_id uuid;
  v_source_assignment_id uuid;
  v_target_assignment_id uuid;
  v_source_assignment_start_week date;
  v_source_assignment_end_week date;
  v_source_group_name text;
  v_membership_role text;
  v_assignment_role text;
  v_next_sort_order integer;
begin
  if p_member_directory_id is null then
    raise exception 'member_directory_id is required.';
  end if;

  if p_target_group_id is null then
    raise exception 'target_group_id is required.';
  end if;

  select *
  into v_member
  from public.member_directory
  where id = p_member_directory_id;

  if not found then
    raise exception 'Member directory row % does not exist.', p_member_directory_id;
  end if;

  select *
  into v_target_group
  from public.groups
  where id = p_target_group_id;

  if not found then
    raise exception 'Target group % does not exist.', p_target_group_id;
  end if;

  if v_target_group.church_id <> v_member.church_id
     or v_target_group.department_id <> v_member.department_id then
    raise exception 'Target group belongs to another church or department.';
  end if;

  if p_source_group_id is not null then
    select *
    into v_source_group
    from public.groups
    where id = p_source_group_id;
  end if;

  v_effective_week := v_requested_week;

  select *
  into v_current_season
  from public.regrouping_seasons s
  where s.church_id = v_member.church_id
    and s.department_id = v_member.department_id
    and s.status = 'applied'
    and s.effective_week_date <= v_today_week
    and (s.end_week_date is null or s.end_week_date >= v_today_week)
  order by s.effective_week_date desc, s.created_at desc
  limit 1;

  if v_current_season.id is null then
    select *
    into v_current_season
    from public.regrouping_seasons s
    where s.church_id = v_member.church_id
      and s.department_id = v_member.department_id
      and s.status = 'applied'
      and s.effective_week_date <= v_requested_week
      and (s.end_week_date is null or s.end_week_date >= v_requested_week)
    order by s.effective_week_date desc, s.created_at desc
    limit 1;
  end if;

  if v_current_season.id is not null then
    if v_effective_week < v_current_season.effective_week_date then
      v_effective_week := v_current_season.effective_week_date;
    end if;

    if v_current_season.end_week_date is not null
       and v_effective_week > v_current_season.end_week_date then
      v_effective_week := v_current_season.end_week_date;
    end if;
  end if;

  v_effective_start := v_effective_week::timestamp with time zone;
  v_source_end := v_effective_start - interval '1 second';
  v_membership_role := case when v_member.role_in_group = 'leader' then 'leader' else 'member' end;
  v_assignment_role := case
    when v_member.role_in_group in ('leader', 'admin', 'sub_leader') then v_member.role_in_group
    else 'member'
  end;

  v_person_id := public.phase2_upsert_person(
    v_member.church_id,
    v_member.person_id,
    v_member.profile_id,
    v_member.id,
    v_member.full_name,
    v_member.phone
  );

  if p_source_group_id is not null then
    update public.memberships m
    set status = 'ended',
        starts_at = least(m.starts_at, v_source_end),
        ends_at = v_source_end,
        updated_at = now()
    where m.person_id = v_person_id
      and m.church_id = v_member.church_id
      and m.department_id = v_member.department_id
      and m.group_id = p_source_group_id
      and m.status = 'active';
  end if;

  select m.id
  into v_target_membership_id
  from public.memberships m
  where m.person_id = v_person_id
    and m.church_id = v_member.church_id
    and m.department_id = v_member.department_id
    and (
      m.group_id = p_target_group_id
      or (
        m.legacy_member_directory_id = v_member.id
        and m.legacy_group_member_id is null
      )
    )
  order by
    case
      when m.group_id = p_target_group_id and m.status = 'active' then 0
      when m.group_id = p_target_group_id then 1
      when m.legacy_member_directory_id = v_member.id and m.legacy_group_member_id is null then 2
      else 3
    end,
    m.updated_at desc nulls last,
    m.starts_at desc nulls last,
    m.id
  limit 1;

  if v_target_membership_id is null then
    insert into public.memberships (
      church_id,
      department_id,
      person_id,
      group_id,
      role,
      status,
      starts_at,
      ends_at,
      legacy_member_directory_id
    )
    values (
      v_member.church_id,
      v_member.department_id,
      v_person_id,
      p_target_group_id,
      v_membership_role,
      'active',
      v_effective_start,
      null,
      v_member.id
    )
    returning id into v_target_membership_id;
  else
    update public.memberships
    set group_id = p_target_group_id,
        role = v_membership_role,
        status = 'active',
        starts_at = v_effective_start,
        ends_at = null,
        legacy_member_directory_id = coalesce(legacy_member_directory_id, v_member.id),
        updated_at = now()
    where id = v_target_membership_id;
  end if;

  if v_current_season.id is not null
     and p_source_group_id is not null
     and p_source_group_id <> p_target_group_id then
    select rpg.id
    into v_source_plan_group_id
    from public.regrouping_plan_groups rpg
    where rpg.season_id = v_current_season.id
      and rpg.source_group_id = p_source_group_id
    order by rpg.sort_order, rpg.name
    limit 1;

    select rpg.id
    into v_target_plan_group_id
    from public.regrouping_plan_groups rpg
    where rpg.season_id = v_current_season.id
      and rpg.source_group_id = p_target_group_id
    order by rpg.sort_order, rpg.name
    limit 1;

    if v_target_plan_group_id is not null then
      v_source_group_name := coalesce(nullif(v_source_group.name, ''), nullif(v_member.group_name, ''));

      select rpa.id
      into v_source_assignment_id
      from public.regrouping_plan_assignments rpa
      where rpa.season_id = v_current_season.id
        and rpa.person_id = v_person_id
        and coalesce(rpa.change_type, '') <> 'removed'
        and rpa.plan_group_id is distinct from v_target_plan_group_id
        and (
          (v_source_plan_group_id is not null and rpa.plan_group_id = v_source_plan_group_id)
          or rpa.source_member_directory_id = v_member.id
          or rpa.source_membership_id in (
            select m.id
            from public.memberships m
            where m.person_id = v_person_id
              and m.church_id = v_member.church_id
              and m.department_id = v_member.department_id
              and m.group_id = p_source_group_id
          )
        )
      order by
        case when v_source_plan_group_id is not null and rpa.plan_group_id = v_source_plan_group_id then 0 else 1 end,
        rpa.sort_order,
        rpa.created_at
      limit 1;

      select rpa.id
      into v_target_assignment_id
      from public.regrouping_plan_assignments rpa
      where rpa.season_id = v_current_season.id
        and rpa.person_id = v_person_id
        and rpa.plan_group_id = v_target_plan_group_id
        and coalesce(rpa.change_type, '') <> 'removed'
      order by rpa.sort_order, rpa.created_at
      limit 1;

      if v_source_assignment_id is not null then
        select coalesce(rpa.starts_week_date, v_current_season.effective_week_date),
               v_effective_week - 7
        into v_source_assignment_start_week,
             v_source_assignment_end_week
        from public.regrouping_plan_assignments rpa
        where rpa.id = v_source_assignment_id;
      end if;

      if v_target_assignment_id is not null then
        update public.regrouping_plan_assignments
        set role_in_group = v_assignment_role,
            change_type = 'moved',
            previous_source_group_id = p_source_group_id,
            previous_group_name = v_source_group_name,
            source_membership_id = v_target_membership_id,
            source_member_directory_id = v_member.id,
            starts_week_date = v_effective_week,
            ends_week_date = v_current_season.end_week_date,
            updated_at = now()
        where id = v_target_assignment_id;

        if v_source_assignment_id is not null
           and v_source_assignment_id <> v_target_assignment_id then
          if v_source_assignment_end_week >= v_source_assignment_start_week then
            update public.regrouping_plan_assignments
            set plan_group_id = coalesce(plan_group_id, v_source_plan_group_id),
                starts_week_date = v_source_assignment_start_week,
                ends_week_date = v_source_assignment_end_week,
                updated_at = now()
            where id = v_source_assignment_id;
          else
            delete from public.regrouping_plan_assignments
            where id = v_source_assignment_id;
          end if;
        end if;
      elsif v_source_assignment_id is not null
            and v_source_assignment_end_week < v_source_assignment_start_week then
        update public.regrouping_plan_assignments
        set plan_group_id = v_target_plan_group_id,
            role_in_group = v_assignment_role,
            change_type = 'moved',
            previous_source_group_id = p_source_group_id,
            previous_group_name = v_source_group_name,
            source_membership_id = v_target_membership_id,
            source_member_directory_id = v_member.id,
            starts_week_date = v_effective_week,
            ends_week_date = v_current_season.end_week_date,
            updated_at = now()
        where id = v_source_assignment_id;
      else
        if v_source_assignment_id is not null then
          update public.regrouping_plan_assignments
          set plan_group_id = coalesce(plan_group_id, v_source_plan_group_id),
              starts_week_date = v_source_assignment_start_week,
              ends_week_date = v_source_assignment_end_week,
              updated_at = now()
          where id = v_source_assignment_id;
        end if;

        select coalesce(max(rpa.sort_order) + 1, 0)
        into v_next_sort_order
        from public.regrouping_plan_assignments rpa
        where rpa.season_id = v_current_season.id
          and rpa.plan_group_id = v_target_plan_group_id;

        insert into public.regrouping_plan_assignments (
          season_id,
          plan_group_id,
          person_id,
          role_in_group,
          sort_order,
          change_type,
          previous_source_group_id,
          previous_group_name,
          source_membership_id,
          source_member_directory_id,
          starts_week_date,
          ends_week_date
        )
        values (
          v_current_season.id,
          v_target_plan_group_id,
          v_person_id,
          v_assignment_role,
          v_next_sort_order,
          'moved',
          p_source_group_id,
          v_source_group_name,
          v_target_membership_id,
          v_member.id,
          v_effective_week,
          v_current_season.end_week_date
        )
        on conflict do nothing;
      end if;
    end if;
  end if;

  update public.member_directory
  set person_id = v_person_id,
      group_name = v_target_group.name,
      role_in_group = coalesce(nullif(role_in_group, ''), 'member'),
      is_active = true,
      left_at = null
  where id = v_member.id
  returning * into v_saved;

  return v_saved;
end;
$$;

grant execute on function public.move_member_directory_to_group(
  uuid,
  uuid,
  uuid,
  date
) to authenticated, service_role;
