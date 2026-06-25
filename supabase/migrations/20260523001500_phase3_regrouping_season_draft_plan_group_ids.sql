-- Phase 3 regrouping season draft RPC fix.
-- Plan group rows must have their own IDs. Reusing live groups.id as
-- regrouping_plan_groups.id breaks multiple seasons for the same source group.

set check_function_bodies = off;

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
  v_assignment jsonb;
  v_plan_group_id uuid;
  v_person_id uuid;
  v_source_membership_id uuid;
  v_source_member_directory_id uuid;
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

  if v_season.status not in ('draft', 'ready') then
    raise exception 'only draft or ready regrouping seasons are editable.';
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
        then nullif(v_group->>'id', '')::uuid
      else null
    end;

    v_leader_person_id := case
      when public.phase3_is_uuid(nullif(v_group->>'leader_person_id', ''))
        then nullif(v_group->>'leader_person_id', '')::uuid
      else null
    end;

    insert into public.regrouping_plan_groups (
      id,
      season_id,
      source_group_id,
      name,
      color_hex,
      sort_order,
      leader_person_id
    )
    values (
      v_group_id,
      p_season_id,
      v_source_group_id,
      v_group_name,
      nullif(v_group->>'color_hex', ''),
      coalesce(nullif(v_group->>'sort_order', '')::integer, 0),
      v_leader_person_id
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
      source_member_directory_id
    )
    values (
      p_season_id,
      v_plan_group_id,
      v_person_id,
      v_role,
      coalesce(nullif(v_assignment->>'sort_order', '')::integer, 0),
      v_source_membership_id,
      v_source_member_directory_id
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

grant execute on function public.save_regrouping_season_draft(
  uuid,
  jsonb,
  jsonb
) to authenticated, service_role;
