-- Guard current-season save against reactivating multiple historical
-- memberships for the same person/group pair. Legacy alias rows can leave
-- several ended membership rows behind; only one row may become active.

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
  v_active_groups jsonb;
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
    plan_status text,
    starts_week_date date,
    ends_week_date date
  ) on commit drop;

  create temporary table if not exists pg_temp.regrouping_effective_assignments (
    client_member_id text,
    member_directory_id uuid,
    person_id uuid,
    group_id uuid,
    group_name text,
    full_name text,
    phone text,
    starts_week_date date,
    ends_week_date date
  ) on commit drop;

  create temporary table if not exists pg_temp.regrouping_effective_membership_targets (
    membership_id uuid primary key
  ) on commit drop;

  truncate table pg_temp.regrouping_effective_saved;
  truncate table pg_temp.regrouping_effective_groups;
  truncate table pg_temp.regrouping_effective_assignments;
  truncate table pg_temp.regrouping_effective_membership_targets;

  select coalesce(jsonb_agg(group_row.value), '[]'::jsonb)
  into v_active_groups
  from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) as group_row(value)
  where coalesce(nullif(group_row.value->>'plan_status', ''), 'active') <> 'ended';

  insert into pg_temp.regrouping_effective_saved (member_directory_id)
  select s.member_directory_id
  from public.save_regrouping_memberships(
    p_church_id,
    p_department_id,
    v_active_groups,
    p_assignments
  ) s
  where s.member_directory_id is not null
  on conflict do nothing;

  insert into pg_temp.regrouping_effective_groups (
    client_group_id,
    group_id,
    group_name,
    plan_status,
    starts_week_date,
    ends_week_date
  )
  select
    nullif(g.value->>'id', ''),
    resolved.id,
    nullif(btrim(g.value->>'name'), ''),
    coalesce(nullif(g.value->>'plan_status', ''), 'active'),
    coalesce(
      case
        when nullif(g.value->>'starts_week_date', '') is not null
          then (g.value->>'starts_week_date')::date
        else null
      end,
      v_effective_start
    ),
    case
      when nullif(g.value->>'ends_week_date', '') is not null
        then (g.value->>'ends_week_date')::date
      else null
    end
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
       resolved.name = nullif(btrim(g.value->>'name'), '')
     )
   )
  where nullif(btrim(g.value->>'name'), '') is not null;

  insert into pg_temp.regrouping_effective_assignments (
    client_member_id,
    member_directory_id,
    person_id,
    group_id,
    group_name,
    full_name,
    phone,
    starts_week_date,
    ends_week_date
  )
  select
    nullif(a.value->>'id', ''),
    case
      when public.phase3_is_uuid(nullif(a.value->>'id', ''))
        then nullif(a.value->>'id', '')::uuid
      else null
    end,
    case
      when public.phase3_is_uuid(nullif(coalesce(a.value->>'phase2_person_id', a.value->>'person_id'), ''))
        then nullif(coalesce(a.value->>'phase2_person_id', a.value->>'person_id'), '')::uuid
      else null
    end,
    eg.group_id,
    eg.group_name,
    nullif(btrim(a.value->>'full_name'), ''),
    public.phase2_normalize_phone(a.value->>'phone'),
    coalesce(
      case
        when nullif(a.value->>'starts_week_date', '') is not null
          then (a.value->>'starts_week_date')::date
        else null
      end,
      v_effective_start
    ),
    case
      when nullif(a.value->>'ends_week_date', '') is not null
        then (a.value->>'ends_week_date')::date
      else null
    end
  from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) as a(value)
  left join pg_temp.regrouping_effective_groups eg
    on eg.client_group_id = nullif(a.value->>'group_id', '')
    or eg.group_id::text = nullif(a.value->>'group_id', '');

  -- Newly created or previously period-less groups should inherit the period
  -- selected in the current-season editor. Existing older groups keep their
  -- earlier active_from so past history is not moved forward accidentally.
  update public.groups g
  set active_from = case
        when g.active_from is null then eg.starts_week_date
        when g.created_at >= v_called_at - interval '5 seconds' then eg.starts_week_date
        when public.phase3_week_start(g.active_from) > eg.starts_week_date then eg.starts_week_date
        else g.active_from
      end
  from pg_temp.regrouping_effective_groups eg
  where eg.group_id = g.id
    and g.church_id = p_church_id
    and g.department_id = p_department_id
    and eg.plan_status <> 'ended'
    and eg.starts_week_date is not null;

  update public.groups g
  set is_active = false,
      ended_at = eg.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second'
  from pg_temp.regrouping_effective_groups eg
  where eg.group_id = g.id
    and g.church_id = p_church_id
    and g.department_id = p_department_id
    and eg.plan_status = 'ended'
    and eg.ends_week_date is not null;

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

  -- Multiple legacy alias rows can point to the same person/group. Only one
  -- membership row may be active for a person/group pair, so choose a single
  -- target row per submitted assignment before applying period/status updates.
  insert into pg_temp.regrouping_effective_membership_targets (membership_id)
  select ranked.membership_id
  from (
    select
      m.id as membership_id,
      row_number() over (
        partition by m.person_id, m.group_id
        order by
          case when m.status = 'active' then 0 else 1 end,
          case when ea.member_directory_id is not null and m.legacy_member_directory_id = ea.member_directory_id then 0 else 1 end,
          m.updated_at desc nulls last,
          m.starts_at desc nulls last,
          m.id
      ) as rn
    from public.memberships m
    join pg_temp.regrouping_effective_assignments ea
      on ea.person_id is not null
     and ea.person_id = m.person_id
     and (
       (ea.group_id is null and m.group_id is null)
       or ea.group_id = m.group_id
     )
    where m.church_id = p_church_id
      and m.department_id = p_department_id
  ) ranked
  where ranked.rn = 1
  on conflict do nothing;

  update public.memberships m
  set starts_at = case
        when ea.starts_week_date is not null
             and (
               m.starts_at is null
               or public.phase3_week_start(m.starts_at::date) > ea.starts_week_date
             )
          then ea.starts_week_date::timestamp with time zone
        else m.starts_at
      end,
      ends_at = case
        when ea.ends_week_date is not null
             and ea.ends_week_date < coalesce(ea.starts_week_date, v_effective_start)
          then m.ends_at
        when ea.ends_week_date is not null
          then (ea.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second')
        else m.ends_at
      end,
      status = case
        when ea.ends_week_date is not null
             and (ea.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second') < now()
          then 'ended'
        else 'active'
      end,
      updated_at = now()
  from pg_temp.regrouping_effective_saved saved
  join public.member_directory md
    on md.id = saved.member_directory_id
  join pg_temp.regrouping_effective_assignments ea
    on true
  where saved.member_directory_id = m.legacy_member_directory_id
    and m.department_id = p_department_id
    and m.church_id = p_church_id
    and exists (
      select 1
      from pg_temp.regrouping_effective_membership_targets target
      where target.membership_id = m.id
    )
    and (
      ea.member_directory_id = md.id
      or (
        ea.person_id is not null
        and ea.person_id = m.person_id
        and (
          (ea.group_id is null and m.group_id is null)
          or ea.group_id = m.group_id
        )
      )
      or (
        ea.full_name = md.full_name
        and coalesce(ea.phone, '') = coalesce(public.phase2_normalize_phone(md.phone), '')
        and coalesce(ea.group_name, '') = coalesce(nullif(btrim(md.group_name), ''), '')
      )
    );

  -- After the season editor saves the full current board, any still-active
  -- membership row that is not represented by the submitted person/group
  -- assignment set is stale. This preserves legitimate multi-group membership
  -- rows because each active group row is present in p_assignments, while
  -- allowing an explicit unassigned row to end all old group memberships.
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
