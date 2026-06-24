-- Prevent future-dated group moves in the current applied season.
-- A future start week behaves like a reservation, but the live directory and
-- membership rows are updated immediately, so current-season moves must be
-- effective no later than the current week.

set check_function_bodies = off;

do $$
declare
  v_function_sql text;
  v_next_function_sql text;
  v_target_block text := $block$
    if v_current_season.end_week_date is not null
       and v_effective_week > v_current_season.end_week_date then
      v_effective_week := v_current_season.end_week_date;
    end if;
$block$;
  v_replacement_block text := $block$
    if v_current_season.end_week_date is not null
       and v_effective_week > v_current_season.end_week_date then
      v_effective_week := v_current_season.end_week_date;
    end if;

    if v_effective_week > v_today_week then
      v_effective_week := v_today_week;
    end if;

    if v_effective_week < v_current_season.effective_week_date then
      v_effective_week := v_current_season.effective_week_date;
    end if;
$block$;
begin
  select pg_get_functiondef('public.move_member_directory_to_group(uuid, uuid, uuid, date)'::regprocedure)
  into v_function_sql;

  v_next_function_sql := replace(v_function_sql, v_target_block, v_replacement_block);

  if v_next_function_sql = v_function_sql then
    raise exception 'Expected current-season end clamp block was not found in move_member_directory_to_group.';
  end if;

  execute v_next_function_sql;
end;
$$;

do $$
declare
  v_function_sql text;
  v_next_function_sql text;
  v_declaration_block text := $block$
  v_effective_start date := coalesce(p_effective_week_date, current_date);
  v_effective_end timestamp with time zone := (coalesce(p_effective_week_date, current_date)::timestamp - interval '1 second');
  v_active_groups jsonb;
$block$;
  v_declaration_replacement text := $block$
  v_effective_start date := coalesce(p_effective_week_date, current_date);
  v_effective_end timestamp with time zone := (coalesce(p_effective_week_date, current_date)::timestamp - interval '1 second');
  v_current_week date := public.phase3_week_start(current_date);
  v_clamp_starts_to_effective_week boolean := false;
  v_active_groups jsonb;
$block$;
  v_truncate_block text := $block$
  truncate table pg_temp.regrouping_effective_saved;
  truncate table pg_temp.regrouping_effective_groups;
  truncate table pg_temp.regrouping_effective_assignments;
  truncate table pg_temp.regrouping_effective_membership_targets;
$block$;
  v_truncate_replacement text := $block$
  truncate table pg_temp.regrouping_effective_saved;
  truncate table pg_temp.regrouping_effective_groups;
  truncate table pg_temp.regrouping_effective_assignments;
  truncate table pg_temp.regrouping_effective_membership_targets;

  select exists (
    select 1
    from public.regrouping_seasons s
    where s.church_id = p_church_id
      and s.department_id = p_department_id
      and s.status = 'applied'
      and s.effective_week_date <= v_current_week
      and (s.end_week_date is null or s.end_week_date >= v_current_week)
  )
  into v_clamp_starts_to_effective_week;

  if v_clamp_starts_to_effective_week
     and v_effective_start > v_current_week then
    v_effective_start := v_current_week;
    v_effective_end := v_current_week::timestamp - interval '1 second';
  end if;
$block$;
  v_groups_insert_end_block text := $block$
  where nullif(btrim(g.value->>'name'), '') is not null;
$block$;
  v_groups_insert_end_replacement text := $block$
  where nullif(btrim(g.value->>'name'), '') is not null;

  if v_clamp_starts_to_effective_week then
    update pg_temp.regrouping_effective_groups
    set starts_week_date = least(starts_week_date, v_effective_start)
    where starts_week_date is not null
      and starts_week_date > v_effective_start;
  end if;
$block$;
  v_assignments_insert_end_block text := $block$
  left join pg_temp.regrouping_effective_groups eg
    on eg.client_group_id = nullif(a.value->>'group_id', '')
    or eg.group_id::text = nullif(a.value->>'group_id', '');

  update pg_temp.regrouping_effective_assignments
$block$;
  v_assignments_insert_end_replacement text := $block$
  left join pg_temp.regrouping_effective_groups eg
    on eg.client_group_id = nullif(a.value->>'group_id', '')
    or eg.group_id::text = nullif(a.value->>'group_id', '');

  if v_clamp_starts_to_effective_week then
    update pg_temp.regrouping_effective_assignments
    set starts_week_date = least(starts_week_date, v_effective_start)
    where starts_week_date is not null
      and starts_week_date > v_effective_start;
  end if;

  update pg_temp.regrouping_effective_assignments
$block$;
begin
  select pg_get_functiondef('public.save_regrouping_memberships(uuid, uuid, jsonb, jsonb, date)'::regprocedure)
  into v_function_sql;

  v_next_function_sql := replace(v_function_sql, v_declaration_block, v_declaration_replacement);
  if v_next_function_sql = v_function_sql then
    raise exception 'Expected declaration block was not found in save_regrouping_memberships.';
  end if;

  v_function_sql := v_next_function_sql;
  v_next_function_sql := replace(v_function_sql, v_truncate_block, v_truncate_replacement);
  if v_next_function_sql = v_function_sql then
    raise exception 'Expected temp table truncate block was not found in save_regrouping_memberships.';
  end if;

  v_function_sql := v_next_function_sql;
  v_next_function_sql := replace(v_function_sql, v_groups_insert_end_block, v_groups_insert_end_replacement);
  if v_next_function_sql = v_function_sql then
    raise exception 'Expected group staging insert block was not found in save_regrouping_memberships.';
  end if;

  v_function_sql := v_next_function_sql;
  v_next_function_sql := replace(v_function_sql, v_assignments_insert_end_block, v_assignments_insert_end_replacement);
  if v_next_function_sql = v_function_sql then
    raise exception 'Expected assignment staging insert block was not found in save_regrouping_memberships.';
  end if;

  execute v_next_function_sql;
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
  v_current_week date := public.phase3_week_start(current_date);
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
    if v_starts_week > v_current_week then
      v_starts_week := v_current_week;
    end if;
    if v_starts_week < v_season.effective_week_date then
      v_starts_week := v_season.effective_week_date;
    end if;

    v_ends_week := coalesce(
      public.phase3_week_start(nullif(v_group->>'ends_week_date', '')::date),
      v_season.end_week_date,
      v_current_week
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

grant execute on function public.update_current_regrouping_group_periods(uuid, jsonb)
to authenticated, service_role;
