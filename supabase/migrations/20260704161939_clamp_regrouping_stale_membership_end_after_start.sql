-- Current-season saves can close stale active membership rows at the moment
-- just before the season effective week. If a duplicate/stale row already has
-- starts_at on the effective week, that produces ends_at < starts_at and trips
-- memberships_check. Clamp stale row end timestamps so they never precede the
-- row's own starts_at.

set check_function_bodies = off;

do $$
declare
  v_function_sql text;
  v_next_function_sql text;
  v_target_block text := $block$
  update public.memberships m
  set status = 'ended',
      ends_at = least(
        coalesce(m.ends_at, '9999-12-31'::timestamp with time zone),
        v_effective_end
      ),
      updated_at = now()
  where m.church_id = p_church_id
    and m.department_id = p_department_id
    and m.status = 'active'
    and not exists (
      select 1
      from pg_temp.regrouping_effective_assignments ea
      where ea.person_id is not null
        and ea.person_id = m.person_id
        and (
          (ea.group_id is null and m.group_id is null)
          or ea.group_id = m.group_id
        )
    );
$block$;
  v_replacement_block text := $block$
  update public.memberships m
  set status = 'ended',
      ends_at = greatest(
        coalesce(m.starts_at, v_effective_end),
        least(
          coalesce(m.ends_at, '9999-12-31'::timestamp with time zone),
          v_effective_end
        )
      ),
      updated_at = now()
  where m.church_id = p_church_id
    and m.department_id = p_department_id
    and m.status = 'active'
    and not exists (
      select 1
      from pg_temp.regrouping_effective_assignments ea
      where ea.person_id is not null
        and ea.person_id = m.person_id
        and (
          (ea.group_id is null and m.group_id is null)
          or ea.group_id = m.group_id
        )
    );
$block$;
begin
  select pg_get_functiondef(
    'public.save_regrouping_memberships_unchecked(uuid, uuid, jsonb, jsonb, date)'::regprocedure
  )
  into v_function_sql;

  v_next_function_sql := replace(v_function_sql, v_target_block, v_replacement_block);

  if v_next_function_sql = v_function_sql then
    raise exception 'Expected stale membership end block was not found in save_regrouping_memberships_unchecked.';
  end if;

  execute v_next_function_sql;
end;
$$;

do $$
declare
  v_function_sql text;
  v_next_function_sql text;
  v_target_block text := $block$
  update public.memberships m
  set status = 'ended',
      ends_at = least(
        coalesce(m.ends_at, v_season.effective_week_date::timestamp with time zone - interval '1 second'),
        v_season.effective_week_date::timestamp with time zone - interval '1 second'
      ),
      updated_at = now()
  where m.church_id = v_season.church_id
    and m.department_id = v_season.department_id
    and m.status = 'active'
    and m.ends_at is not null
    and m.ends_at < v_season.effective_week_date::timestamp with time zone
    and not exists (
      select 1
      from pg_temp.regrouping_live_membership_targets targets
      where targets.membership_id = m.id
    );
$block$;
  v_replacement_block text := $block$
  update public.memberships m
  set status = 'ended',
      ends_at = greatest(
        coalesce(m.starts_at, v_season.effective_week_date::timestamp with time zone - interval '1 second'),
        least(
          coalesce(m.ends_at, v_season.effective_week_date::timestamp with time zone - interval '1 second'),
          v_season.effective_week_date::timestamp with time zone - interval '1 second'
        )
      ),
      updated_at = now()
  where m.church_id = v_season.church_id
    and m.department_id = v_season.department_id
    and m.status = 'active'
    and m.ends_at is not null
    and m.ends_at < v_season.effective_week_date::timestamp with time zone
    and not exists (
      select 1
      from pg_temp.regrouping_live_membership_targets targets
      where targets.membership_id = m.id
    );
$block$;
begin
  select pg_get_functiondef(
    'public.repair_applied_regrouping_live_state(uuid)'::regprocedure
  )
  into v_function_sql;

  v_next_function_sql := replace(v_function_sql, v_target_block, v_replacement_block);

  if v_next_function_sql = v_function_sql then
    raise exception 'Expected stale membership repair block was not found in repair_applied_regrouping_live_state.';
  end if;

  execute v_next_function_sql;
end;
$$;
