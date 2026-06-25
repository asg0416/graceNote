-- Phase 3 regrouping plan group status:
-- Keep groups that were active during a current season but later removed as
-- ended plan rows. This lets the admin UI correct their operating period
-- without showing them as active Kanban columns.

set check_function_bodies = off;

alter table public.regrouping_plan_groups
  add column if not exists plan_status text not null default 'active';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_groups_plan_status_check'
      and conrelid = 'public.regrouping_plan_groups'::regclass
  ) then
    alter table public.regrouping_plan_groups
      add constraint regrouping_plan_groups_plan_status_check
      check (plan_status in ('active', 'ended'));
  end if;
end;
$$;

create index if not exists regrouping_plan_groups_status_idx
on public.regrouping_plan_groups (season_id, plan_status);

create or replace function public.save_regrouping_season_draft(
  p_season_id uuid,
  p_groups jsonb,
  p_assignments jsonb
)
returns table(plan_group_count integer, assignment_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_group jsonb;
  v_group_id uuid;
  v_source_group_id uuid;
  v_leader_person_id uuid;
  v_group_name text;
  v_group_status text;
  v_group_starts_week date;
  v_group_ends_week date;
  v_assignment jsonb;
  v_plan_group_id uuid;
  v_person_id uuid;
  v_source_membership_id uuid;
  v_source_member_directory_id uuid;
  v_assignment_starts_week date;
  v_assignment_ends_week date;
  v_role text;
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
    raise exception 'not allowed to save regrouping season.';
  end if;

  if not (
    v_season.status in ('draft', 'ready')
    or (
      v_season.status = 'applied'
      and public.phase3_regrouping_season_is_current(
        v_season.effective_week_date,
        v_season.end_week_date
      )
    )
  ) then
    raise exception 'only draft, ready, or current applied regrouping seasons are editable.';
  end if;

  create temporary table if not exists pg_temp.regrouping_plan_group_input (
    client_group_id text primary key,
    plan_group_id uuid not null
  ) on commit drop;

  truncate table pg_temp.regrouping_plan_group_input;

  delete from public.regrouping_plan_assignments
  where season_id = p_season_id;

  delete from public.regrouping_plan_groups
  where season_id = p_season_id;

  for v_group in
    select value
    from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) as g(value)
  loop
    v_group_name := nullif(btrim(v_group->>'name'), '');
    if v_group_name is null then
      continue;
    end if;

    v_group_id := case
      when public.phase3_is_uuid(nullif(v_group->>'plan_group_id', ''))
        then nullif(v_group->>'plan_group_id', '')::uuid
      else gen_random_uuid()
    end;

    v_source_group_id := case
      when public.phase3_is_uuid(nullif(v_group->>'source_group_id', ''))
        then nullif(v_group->>'source_group_id', '')::uuid
      when public.phase3_is_uuid(nullif(v_group->>'id', ''))
           and not public.phase3_is_uuid(nullif(v_group->>'plan_group_id', ''))
        then nullif(v_group->>'id', '')::uuid
      else null
    end;

    v_leader_person_id := case
      when public.phase3_is_uuid(nullif(v_group->>'leader_person_id', ''))
        then nullif(v_group->>'leader_person_id', '')::uuid
      else null
    end;

    v_group_status := case
      when v_group->>'plan_status' = 'ended' then 'ended'
      else 'active'
    end;

    v_group_starts_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'starts_week_date', '')::date),
      v_season.effective_week_date
    );
    v_group_ends_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'ends_week_date', '')::date),
      v_season.end_week_date
    );

    if v_group_status = 'ended' and v_group_ends_week is null then
      v_group_ends_week := coalesce(v_season.end_week_date, public.phase3_week_start(current_date));
    end if;

    if v_group_ends_week is not null and v_group_ends_week < v_group_starts_week then
      raise exception 'group end week must be on or after start week.';
    end if;

    insert into public.regrouping_plan_groups (
      id,
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
    values (
      v_group_id,
      p_season_id,
      v_source_group_id,
      v_group_name,
      nullif(v_group->>'color_hex', ''),
      coalesce(nullif(v_group->>'sort_order', '')::integer, 0),
      v_leader_person_id,
      v_group_starts_week,
      v_group_ends_week,
      v_group_status
    );

    if nullif(v_group->>'id', '') is not null then
      insert into pg_temp.regrouping_plan_group_input (client_group_id, plan_group_id)
      values (v_group->>'id', v_group_id)
      on conflict (client_group_id) do update
      set plan_group_id = excluded.plan_group_id;
    end if;

    insert into pg_temp.regrouping_plan_group_input (client_group_id, plan_group_id)
    values (v_group_id::text, v_group_id)
    on conflict (client_group_id) do update
    set plan_group_id = excluded.plan_group_id;
  end loop;

  for v_assignment in
    select value
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) as a(value)
  loop
    v_person_id := case
      when public.phase3_is_uuid(nullif(coalesce(v_assignment->>'person_id', v_assignment->>'phase2_person_id'), ''))
        then nullif(coalesce(v_assignment->>'person_id', v_assignment->>'phase2_person_id'), '')::uuid
      else null
    end;

    if v_person_id is null then
      continue;
    end if;

    v_plan_group_id := case
      when public.phase3_is_uuid(nullif(v_assignment->>'plan_group_id', ''))
        then nullif(v_assignment->>'plan_group_id', '')::uuid
      when nullif(v_assignment->>'group_id', '') is not null
        then (
          select m.plan_group_id
          from pg_temp.regrouping_plan_group_input m
          where m.client_group_id = v_assignment->>'group_id'
          limit 1
        )
      else null
    end;

    v_source_membership_id := case
      when public.phase3_is_uuid(nullif(v_assignment->>'source_membership_id', ''))
        then nullif(v_assignment->>'source_membership_id', '')::uuid
      when public.phase3_is_uuid(nullif(v_assignment->>'membership_id', ''))
        then nullif(v_assignment->>'membership_id', '')::uuid
      else null
    end;

    v_source_member_directory_id := case
      when public.phase3_is_uuid(nullif(v_assignment->>'source_member_directory_id', ''))
        then nullif(v_assignment->>'source_member_directory_id', '')::uuid
      when public.phase3_is_uuid(nullif(v_assignment->>'id', ''))
        then nullif(v_assignment->>'id', '')::uuid
      else null
    end;

    v_assignment_starts_week := coalesce(
      public.phase3_week_start(nullif(v_assignment->>'starts_week_date', '')::date),
      v_season.effective_week_date
    );
    v_assignment_ends_week := coalesce(
      public.phase3_week_start(nullif(v_assignment->>'ends_week_date', '')::date),
      v_season.end_week_date
    );

    if v_assignment_ends_week is not null and v_assignment_ends_week < v_assignment_starts_week then
      raise exception 'assignment end week must be on or after start week.';
    end if;

    v_role := coalesce(nullif(v_assignment->>'role_in_group', ''), nullif(v_assignment->>'role', ''), 'member');
    if v_role not in ('leader', 'member', 'admin', 'sub_leader') then
      v_role := 'member';
    end if;

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
    values (
      p_season_id,
      v_plan_group_id,
      v_person_id,
      v_role,
      coalesce(nullif(v_assignment->>'sort_order', '')::integer, 0),
      v_source_membership_id,
      v_source_member_directory_id,
      v_assignment_starts_week,
      v_assignment_ends_week
    )
    on conflict do nothing;
  end loop;

  update public.regrouping_seasons
  set updated_at = now()
  where id = p_season_id;

  return query
  select
    (select count(*)::integer from public.regrouping_plan_groups where season_id = p_season_id),
    (select count(*)::integer from public.regrouping_plan_assignments where season_id = p_season_id);
end;
$$;

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
  select
    p_season_id,
    g.id,
    g.name,
    g.color_hex,
    row_number() over (order by case when g.is_active is false then 1 else 0 end, lower(g.name), g.created_at, g.id)::integer - 1,
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
    ),
    greatest(coalesce(public.phase3_week_start(g.active_from), v_season.effective_week_date), v_season.effective_week_date),
    case
      when g.is_active is false and g.ended_at is not null
        then greatest(public.phase3_week_start(g.ended_at::date), v_season.effective_week_date)
      else v_season.end_week_date
    end,
    case when g.is_active is false then 'ended' else 'active' end
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
  order by case when g.is_active is false then 1 else 0 end, lower(g.name), g.created_at, g.id;

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
    left join public.regrouping_plan_groups rpg
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
    v_ends_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'ends_week_date', '')::date),
      v_season.end_week_date,
      public.phase3_week_start(current_date)
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

create or replace function public.apply_regrouping_season(p_season_id uuid)
returns table(
  created_group_count integer,
  ended_group_count integer,
  created_membership_count integer,
  ended_membership_count integer,
  affected_person_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_groups jsonb := '[]'::jsonb;
  v_assignments jsonb := '[]'::jsonb;
  v_ended_group_count integer := 0;
  v_ended_membership_count integer := 0;
  v_saved_count integer := 0;
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
    raise exception 'not allowed to apply regrouping season.';
  end if;

  if v_season.status = 'applied' then
    raise exception 'regrouping season already applied.';
  end if;

  if v_season.status in ('cancelled', 'archived') then
    raise exception 'cancelled or archived regrouping seasons cannot be applied.';
  end if;

  if v_season.effective_week_date > current_date then
    raise exception 'future regrouping seasons cannot be applied before the effective week.';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', coalesce(rpg.source_group_id::text, 'plan-' || rpg.id::text),
      'source_group_id', rpg.source_group_id,
      'name', rpg.name,
      'color_hex', rpg.color_hex,
      'sort_order', rpg.sort_order,
      'leader_person_id', rpg.leader_person_id
    )
    order by rpg.sort_order, rpg.name
  ), '[]'::jsonb)
  into v_groups
  from public.regrouping_plan_groups rpg
  where rpg.season_id = p_season_id
    and rpg.plan_status = 'active';

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', rpa.source_member_directory_id,
      'group_id', case
        when rpg.id is null then null
        else coalesce(rpg.source_group_id::text, 'plan-' || rpg.id::text)
      end,
      'full_name', coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), nullif(p.display_name, ''), '이름 없음'),
      'phone', coalesce(nullif(md.phone, ''), nullif(mp.phone, ''), nullif(p.normalized_phone, ''), ''),
      'role_in_group', case when rpa.role_in_group = 'leader' then 'leader' else 'member' end,
      'family_name', md.family_name,
      'spouse_name', md.spouse_name,
      'children_info', md.children_info,
      'birth_date', md.birth_date,
      'wedding_anniversary', md.wedding_anniversary,
      'notes', md.notes,
      'avatar_url', coalesce(md.avatar_url, mp.avatar_url),
      'person_id', rpa.person_id,
      'phase2_person_id', rpa.person_id,
      'phase2_membership_id', rpa.source_membership_id,
      'profile_id', coalesce(md.profile_id, mp.profile_id),
      'sort_order', rpa.sort_order
    )
    order by rpg.sort_order nulls last, rpa.sort_order
  ), '[]'::jsonb)
  into v_assignments
  from public.regrouping_plan_assignments rpa
  left join public.regrouping_plan_groups rpg
    on rpg.id = rpa.plan_group_id
   and rpg.plan_status = 'active'
  join public.people p
    on p.id = rpa.person_id
  left join public.member_directory md
    on md.id = rpa.source_member_directory_id
  left join lateral (
    select mp.*
    from public.member_profiles mp
    where mp.person_id = rpa.person_id
    order by
      case when mp.member_directory_id = rpa.source_member_directory_id then 0 else 1 end,
      mp.updated_at desc nulls last,
      mp.created_at desc
    limit 1
  ) mp on true
  where rpa.season_id = p_season_id;

  select count(*)::integer
  into v_ended_group_count
  from public.groups g
  where g.church_id = v_season.church_id
    and g.department_id = v_season.department_id
    and g.is_active is not false
    and not exists (
      select 1
      from public.regrouping_plan_groups rpg
      where rpg.season_id = p_season_id
        and rpg.source_group_id = g.id
        and rpg.plan_status = 'active'
    );

  select count(*)::integer
  into v_ended_membership_count
  from public.memberships m
  where m.church_id = v_season.church_id
    and m.department_id = v_season.department_id
    and m.status = 'active'
    and not exists (
      select 1
      from public.regrouping_plan_assignments rpa
      where rpa.season_id = p_season_id
        and rpa.person_id = m.person_id
    );

  with saved as (
    select *
    from public.save_regrouping_memberships(
      v_season.church_id,
      v_season.department_id,
      v_groups,
      v_assignments,
      v_season.effective_week_date
    )
  )
  select count(*)::integer
  into v_saved_count
  from saved;

  update public.regrouping_seasons
  set status = 'applied',
      applied_at = now(),
      applied_by = auth.uid(),
      updated_at = now()
  where id = p_season_id;

  return query
  select
    (
      select count(*)::integer
      from public.regrouping_plan_groups rpg
      where rpg.season_id = p_season_id
        and rpg.source_group_id is null
        and rpg.plan_status = 'active'
    ),
    v_ended_group_count,
    v_saved_count,
    v_ended_membership_count,
    (
      select count(distinct rpa.person_id)::integer
      from public.regrouping_plan_assignments rpa
      where rpa.season_id = p_season_id
    );
end;
$$;

grant execute on function public.save_regrouping_season_draft(uuid, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.sync_current_regrouping_season_plan_from_live(uuid) to authenticated, service_role;
grant execute on function public.update_current_regrouping_group_periods(uuid, jsonb) to authenticated, service_role;
grant execute on function public.apply_regrouping_season(uuid) to authenticated, service_role;
