-- Persist season assignment change metadata so current-season edit history
-- remains visible after draft save/reload. This is UI/planning metadata only;
-- live memberships remain the source of actual app visibility.

set check_function_bodies = off;

alter table public.regrouping_plan_assignments
  add column if not exists change_type text,
  add column if not exists previous_source_group_id uuid references public.groups(id) on delete set null,
  add column if not exists previous_group_name text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_plan_assignments_change_type_check'
      and conrelid = 'public.regrouping_plan_assignments'::regclass
  ) then
    alter table public.regrouping_plan_assignments
      add constraint regrouping_plan_assignments_change_type_check
      check (
        change_type is null
        or change_type in ('moved', 'added', 'removed', 'period')
      );
  end if;
end $$;

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
  v_is_new_member_group boolean;
  v_climbing_threshold integer;
  v_assignment jsonb;
  v_plan_group_id uuid;
  v_person_id uuid;
  v_source_membership_id uuid;
  v_source_member_directory_id uuid;
  v_previous_source_group_id uuid;
  v_assignment_starts_week date;
  v_assignment_ends_week date;
  v_role text;
  v_change_type text;
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
    v_is_new_member_group := coalesce((v_group->>'is_new_member_group')::boolean, false);
    v_climbing_threshold := case
      when v_is_new_member_group then coalesce(nullif(v_group->>'climbing_threshold', '')::integer, 4)
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
      plan_status,
      is_new_member_group,
      climbing_threshold
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
      v_group_status,
      v_is_new_member_group,
      v_climbing_threshold
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

    v_previous_source_group_id := case
      when public.phase3_is_uuid(nullif(v_assignment->>'previous_source_group_id', ''))
        then nullif(v_assignment->>'previous_source_group_id', '')::uuid
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

    v_change_type := nullif(v_assignment->>'change_type', '');
    if v_change_type not in ('moved', 'added', 'removed', 'period') then
      v_change_type := null;
    end if;

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
      p_season_id,
      v_plan_group_id,
      v_person_id,
      v_role,
      coalesce(nullif(v_assignment->>'sort_order', '')::integer, 0),
      v_change_type,
      v_previous_source_group_id,
      nullif(btrim(v_assignment->>'previous_group_name'), ''),
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

grant execute on function public.save_regrouping_season_draft(uuid, jsonb, jsonb) to authenticated, service_role;

-- Keep already saved "removed from group" rows visible after this migration.
-- Older rows only had plan_group_id = null, so preserve the prior group label
-- from source membership/member_directory where possible.
update public.regrouping_plan_assignments rpa
set
  change_type = coalesce(rpa.change_type, 'removed'),
  previous_source_group_id = coalesce(rpa.previous_source_group_id, m.group_id),
  previous_group_name = coalesce(rpa.previous_group_name, g.name)
from public.memberships m
left join public.groups g on g.id = m.group_id
where rpa.plan_group_id is null
  and rpa.source_membership_id = m.id
  and (
    rpa.change_type is null
    or rpa.previous_source_group_id is null
    or rpa.previous_group_name is null
  );

update public.regrouping_plan_assignments rpa
set
  change_type = coalesce(rpa.change_type, 'removed'),
  previous_group_name = coalesce(rpa.previous_group_name, md.group_name)
from public.member_directory md
where rpa.plan_group_id is null
  and rpa.source_member_directory_id = md.id
  and md.group_name is not null
  and (
    rpa.change_type is null
    or rpa.previous_group_name is null
  );
