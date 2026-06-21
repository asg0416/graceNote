-- Current-season regrouping edits should only change group memberships.
-- Ending a group assignment must not deactivate the person's department roster
-- row in member_directory.

set check_function_bodies = off;

do $$
declare
  v_function_sql text;
  v_next_function_sql text;
  v_removed_block text := $block$
  update public.member_directory md
  set is_active = false,
      left_at = least(
        coalesce(md.left_at, '9999-12-31'::timestamp with time zone),
        ea.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second'
      )
  from pg_temp.regrouping_effective_saved saved
  join pg_temp.regrouping_effective_assignments ea
    on ea.member_directory_id = saved.member_directory_id
  where md.id = saved.member_directory_id
    and ea.ends_week_date is not null
    and (ea.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second') < now();
$block$;
begin
  select pg_get_functiondef('public.save_regrouping_memberships(uuid, uuid, jsonb, jsonb, date)'::regprocedure)
  into v_function_sql;

  v_next_function_sql := replace(
    v_function_sql,
    v_removed_block,
    E'  -- Intentionally keep member_directory rows active.\\n  -- Group assignment end dates are membership history, not department deactivation.'
  );

  if v_next_function_sql = v_function_sql then
    raise exception 'Expected member_directory deactivation block was not found in save_regrouping_memberships.';
  end if;

  execute v_next_function_sql;
end;
$$;
