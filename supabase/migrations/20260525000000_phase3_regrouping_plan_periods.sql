-- Phase 3 regrouping plan periods:
-- Store group/member period boundaries inside season drafts. Future seasons
-- still use the season-wide period by default; current seasons can later expose
-- per-group and per-member period correction UI without changing the storage
-- model again.

set check_function_bodies = off;

create or replace function public.phase3_week_start(p_date date)
returns date
language sql
immutable
strict
as $$
  select (p_date - extract(dow from p_date)::integer)::date;
$$;

alter table public.regrouping_plan_groups
  add column if not exists starts_week_date date,
  add column if not exists ends_week_date date;

alter table public.regrouping_plan_assignments
  add column if not exists starts_week_date date,
  add column if not exists ends_week_date date;

update public.regrouping_plan_groups rpg
set starts_week_date = coalesce(rpg.starts_week_date, s.effective_week_date),
    ends_week_date = coalesce(rpg.ends_week_date, s.end_week_date)
from public.regrouping_seasons s
where s.id = rpg.season_id
  and (rpg.starts_week_date is null or (rpg.ends_week_date is null and s.end_week_date is not null));

update public.regrouping_plan_assignments rpa
set starts_week_date = coalesce(rpa.starts_week_date, s.effective_week_date),
    ends_week_date = coalesce(rpa.ends_week_date, s.end_week_date)
from public.regrouping_seasons s
where s.id = rpa.season_id
  and (rpa.starts_week_date is null or (rpa.ends_week_date is null and s.end_week_date is not null));

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_groups_starts_week_sunday_check'
      and conrelid = 'public.regrouping_plan_groups'::regclass
  ) then
    alter table public.regrouping_plan_groups
      add constraint regrouping_plan_groups_starts_week_sunday_check
      check (starts_week_date is null or extract(dow from starts_week_date)::integer = 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_groups_ends_week_sunday_check'
      and conrelid = 'public.regrouping_plan_groups'::regclass
  ) then
    alter table public.regrouping_plan_groups
      add constraint regrouping_plan_groups_ends_week_sunday_check
      check (ends_week_date is null or extract(dow from ends_week_date)::integer = 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_groups_period_order_check'
      and conrelid = 'public.regrouping_plan_groups'::regclass
  ) then
    alter table public.regrouping_plan_groups
      add constraint regrouping_plan_groups_period_order_check
      check (starts_week_date is null or ends_week_date is null or ends_week_date >= starts_week_date);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_assignments_starts_week_sunday_check'
      and conrelid = 'public.regrouping_plan_assignments'::regclass
  ) then
    alter table public.regrouping_plan_assignments
      add constraint regrouping_plan_assignments_starts_week_sunday_check
      check (starts_week_date is null or extract(dow from starts_week_date)::integer = 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_assignments_ends_week_sunday_check'
      and conrelid = 'public.regrouping_plan_assignments'::regclass
  ) then
    alter table public.regrouping_plan_assignments
      add constraint regrouping_plan_assignments_ends_week_sunday_check
      check (ends_week_date is null or extract(dow from ends_week_date)::integer = 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_assignments_period_order_check'
      and conrelid = 'public.regrouping_plan_assignments'::regclass
  ) then
    alter table public.regrouping_plan_assignments
      add constraint regrouping_plan_assignments_period_order_check
      check (starts_week_date is null or ends_week_date is null or ends_week_date >= starts_week_date);
  end if;
end;
$$;

create index if not exists regrouping_plan_groups_period_idx
on public.regrouping_plan_groups (season_id, starts_week_date, ends_week_date);

create index if not exists regrouping_plan_assignments_period_idx
on public.regrouping_plan_assignments (season_id, starts_week_date, ends_week_date);

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

    v_group_starts_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'starts_week_date', '')::date),
      v_season.effective_week_date
    );
    v_group_ends_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'ends_week_date', '')::date),
      v_season.end_week_date
    );

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
      ends_week_date
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
      v_group_ends_week
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
    leader_person_id,
    starts_week_date,
    ends_week_date
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
    ),
    greatest(coalesce(public.phase3_week_start(g.active_from), p_effective_week_date), p_effective_week_date),
    p_end_week_date
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
      coalesce(p.display_name, md.full_name, '') as display_name,
      greatest(coalesce(public.phase3_week_start(cm.starts_at::date), p_effective_week_date), p_effective_week_date) as starts_week_date
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
    mapped.legacy_member_directory_id,
    mapped.starts_week_date,
    p_end_week_date
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
    leader_person_id,
    starts_week_date,
    ends_week_date
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
    ),
    greatest(coalesce(public.phase3_week_start(g.active_from), v_season.effective_week_date), v_season.effective_week_date),
    v_season.end_week_date
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

grant execute on function public.phase3_week_start(date) to authenticated, service_role;
grant execute on function public.save_regrouping_season_draft(uuid, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.register_current_regrouping_season(uuid, uuid, text, date, date) to authenticated, service_role;
grant execute on function public.register_current_regrouping_season(uuid, uuid, text, date) to authenticated, service_role;
grant execute on function public.sync_current_regrouping_season_plan_from_live(uuid) to authenticated, service_role;
