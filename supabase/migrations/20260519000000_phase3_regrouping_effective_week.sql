-- Let regrouping saves carry the week from which the new arrangement should
-- be considered effective. This keeps historical prayer/attendance screens
-- aligned with church operating periods instead of the admin save timestamp.

set check_function_bodies = off;

create or replace function public.save_regrouping_memberships(
  p_church_id uuid,
  p_department_id uuid,
  p_groups jsonb,
  p_assignments jsonb,
  p_effective_week_date date
)
returns table(member_directory_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_called_at timestamp with time zone := now();
  v_effective_start date := coalesce(p_effective_week_date, current_date);
  v_effective_end timestamp with time zone := (coalesce(p_effective_week_date, current_date)::timestamp - interval '1 second');
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  create temporary table if not exists pg_temp.regrouping_effective_saved (
    member_directory_id uuid primary key
  ) on commit drop;

  create temporary table if not exists pg_temp.regrouping_effective_groups (
    client_group_id text,
    group_id uuid,
    group_name text,
    is_new_client_group boolean default false
  ) on commit drop;

  truncate table pg_temp.regrouping_effective_saved;
  truncate table pg_temp.regrouping_effective_groups;

  insert into pg_temp.regrouping_effective_saved (member_directory_id)
  select s.member_directory_id
  from public.save_regrouping_memberships(
    p_church_id,
    p_department_id,
    p_groups,
    p_assignments
  ) s
  where s.member_directory_id is not null
  on conflict do nothing;

  insert into pg_temp.regrouping_effective_groups (
    client_group_id,
    group_id,
    group_name,
    is_new_client_group
  )
  select
    nullif(g.value->>'id', ''),
    resolved.id,
    nullif(btrim(g.value->>'name'), ''),
    not public.phase3_is_uuid(nullif(g.value->>'id', ''))
  from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) as g(value)
  left join public.groups resolved
    on resolved.church_id = p_church_id
   and resolved.department_id = p_department_id
   and (
     (
       public.phase3_is_uuid(nullif(g.value->>'id', ''))
       and resolved.id = nullif(g.value->>'id', '')::uuid
     )
     or (
       not public.phase3_is_uuid(nullif(g.value->>'id', ''))
       and resolved.name = nullif(btrim(g.value->>'name'), '')
     )
   )
  where nullif(btrim(g.value->>'name'), '') is not null;

  -- Newly created client-side groups should begin on the selected effective
  -- week, not the admin save date. Existing groups keep their earlier
  -- active_from unless they had no period value yet.
  update public.groups g
  set active_from = case
      when eg.is_new_client_group then v_effective_start
      else coalesce(g.active_from, v_effective_start)
    end
  from pg_temp.regrouping_effective_groups eg
  where eg.group_id = g.id
    and g.church_id = p_church_id
    and g.department_id = p_department_id;

  -- The 4-arg compatibility RPC soft-ends removed groups at save time. Move
  -- only those just-ended rows to the selected effective boundary.
  update public.groups g
  set ended_at = v_effective_end
  where g.church_id = p_church_id
    and g.department_id = p_department_id
    and g.is_active = false
    and g.ended_at >= v_called_at - interval '5 seconds'
    and not exists (
      select 1
      from pg_temp.regrouping_effective_groups eg
      where eg.group_id = g.id
    );

  update public.member_directory md
  set left_at = v_effective_end
  where md.church_id = p_church_id
    and md.department_id = p_department_id
    and md.is_active = false
    and md.left_at >= v_called_at - interval '5 seconds'
    and not exists (
      select 1
      from pg_temp.regrouping_effective_saved saved
      where saved.member_directory_id = md.id
    );

  update public.memberships m
  set ends_at = v_effective_end,
      updated_at = now()
  where m.department_id = p_department_id
    and m.status = 'ended'
    and m.ends_at >= v_called_at - interval '5 seconds';

  update public.memberships m
  set starts_at = case
        when m.starts_at is null then v_effective_start::timestamp with time zone
        when m.starts_at > v_effective_start::timestamp with time zone then v_effective_start::timestamp with time zone
        else m.starts_at
      end,
      updated_at = now()
  from pg_temp.regrouping_effective_saved saved
  where saved.member_directory_id = m.legacy_member_directory_id
    and m.department_id = p_department_id
    and m.status = 'active';

  return query
  select saved.member_directory_id
  from pg_temp.regrouping_effective_saved saved;
end;
$$;

grant execute on function public.save_regrouping_memberships(
  uuid,
  uuid,
  jsonb,
  jsonb,
  date
) to authenticated, service_role;
