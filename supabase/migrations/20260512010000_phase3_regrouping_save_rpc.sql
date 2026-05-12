-- Phase 3 regrouping save RPC:
-- Move admin regrouping writes behind one database entry point. The function
-- still maintains legacy member_directory/group_members compatibility rows,
-- but the caller no longer orchestrates many direct legacy writes.

set check_function_bodies = off;

create or replace function public.phase3_is_uuid(p_value text)
returns boolean
language sql
immutable
as $$
  select p_value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;

create or replace function public.sync_directory_to_group_members()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
  v_group_member_id uuid;
begin
  if NEW.profile_id is null then
    return NEW;
  end if;

  select id
  into v_group_id
  from public.groups
  where church_id = NEW.church_id
    and department_id = NEW.department_id
    and name = NEW.group_name
    and is_active = true
  limit 1;

  if not coalesce(NEW.is_active, true) or v_group_id is null then
    update public.group_members
    set is_active = false
    where member_directory_id = NEW.id
      and is_active = true;

    return NEW;
  end if;

  insert into public.group_members (
    group_id,
    profile_id,
    member_directory_id,
    role_in_group,
    is_active,
    joined_at
  )
  values (
    v_group_id,
    NEW.profile_id,
    NEW.id,
    case when NEW.role_in_group = 'leader' then 'leader' else 'member' end,
    true,
    coalesce(NEW.joined_at, now())
  )
  on conflict (group_id, member_directory_id) do update
  set profile_id = excluded.profile_id,
      role_in_group = excluded.role_in_group,
      is_active = true
  returning id into v_group_member_id;

  update public.group_members
  set is_active = false
  where member_directory_id = NEW.id
    and id <> v_group_member_id
    and is_active = true;

  return NEW;
end;
$$;

create or replace function public.save_regrouping_memberships(
  p_church_id uuid,
  p_department_id uuid,
  p_groups jsonb,
  p_assignments jsonb
)
returns table(member_directory_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamp with time zone := now();
  v_group jsonb;
  v_assignment jsonb;
  v_client_group_id text;
  v_group_id uuid;
  v_group_name text;
  v_group_color text;
  v_member_directory_id uuid;
  v_reusable_member_directory_id uuid;
  v_existing_member public.member_directory%rowtype;
  v_saved public.member_directory%rowtype;
  v_role_in_group text;
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  create temporary table if not exists pg_temp.regrouping_group_map (
    client_group_id text primary key,
    group_id uuid not null,
    group_name text not null
  ) on commit drop;

  create temporary table if not exists pg_temp.regrouping_assignment_map (
    client_member_id text,
    member_directory_id uuid,
    person_id uuid,
    group_id uuid,
    group_name text,
    full_name text,
    phone text
  ) on commit drop;

  truncate table pg_temp.regrouping_group_map;
  truncate table pg_temp.regrouping_assignment_map;

  for v_group in select * from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb))
  loop
    v_client_group_id := nullif(v_group->>'id', '');
    v_group_name := nullif(btrim(v_group->>'name'), '');
    v_group_color := nullif(v_group->>'color_hex', '');

    if v_group_name is null then
      continue;
    end if;

    if public.phase3_is_uuid(v_client_group_id) then
      update public.groups
      set name = v_group_name,
          color_hex = coalesce(v_group_color, color_hex),
          department_id = p_department_id,
          church_id = p_church_id,
          is_active = true,
          ended_at = null
      where id = v_client_group_id::uuid
        and church_id = p_church_id
      returning id into v_group_id;
    else
      v_group_id := null;
    end if;

    if v_group_id is null then
      insert into public.groups (
        church_id,
        department_id,
        name,
        color_hex,
        is_active,
        ended_at
      )
      values (
        p_church_id,
        p_department_id,
        v_group_name,
        coalesce(v_group_color, '#4f46e5'),
        true,
        null
      )
      on conflict (church_id, department_id, name) do update
      set color_hex = coalesce(excluded.color_hex, public.groups.color_hex),
          is_active = true,
          ended_at = null
      returning id into v_group_id;
    end if;

    insert into pg_temp.regrouping_group_map (client_group_id, group_id, group_name)
    values (coalesce(v_client_group_id, v_group_id::text), v_group_id, v_group_name)
    on conflict (client_group_id) do update
    set group_id = excluded.group_id,
        group_name = excluded.group_name;
  end loop;

  update public.groups g
  set is_active = false,
      ended_at = coalesce(g.ended_at, v_now)
  where g.church_id = p_church_id
    and g.department_id = p_department_id
    and g.is_active = true
    and not exists (
      select 1
      from pg_temp.regrouping_group_map gm
      where gm.group_id = g.id
    );

  for v_assignment in select * from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb))
  loop
    v_client_group_id := nullif(v_assignment->>'group_id', '');
    v_group_id := null;
    v_group_name := null;

    if v_client_group_id is not null then
      select gm.group_id, gm.group_name
      into v_group_id, v_group_name
      from pg_temp.regrouping_group_map gm
      where gm.client_group_id = v_client_group_id
         or gm.group_id::text = v_client_group_id
      limit 1;
    end if;

    v_member_directory_id := null;
    if public.phase3_is_uuid(nullif(v_assignment->>'id', '')) then
      v_member_directory_id := (v_assignment->>'id')::uuid;
    end if;

    insert into pg_temp.regrouping_assignment_map (
      client_member_id,
      member_directory_id,
      person_id,
      group_id,
      group_name,
      full_name,
      phone
    )
    values (
      nullif(v_assignment->>'id', ''),
      v_member_directory_id,
      case when public.phase3_is_uuid(nullif(coalesce(v_assignment->>'phase2_person_id', v_assignment->>'person_id'), ''))
        then nullif(coalesce(v_assignment->>'phase2_person_id', v_assignment->>'person_id'), '')::uuid
        else null
      end,
      v_group_id,
      v_group_name,
      nullif(btrim(v_assignment->>'full_name'), ''),
      public.phase2_normalize_phone(v_assignment->>'phone')
    );
  end loop;

  if exists (
    select 1
    from pg_temp.regrouping_assignment_map a
    where a.group_id is not null
    group by a.group_id, coalesce(a.person_id::text, a.full_name || '|' || coalesce(a.phone, ''))
    having count(*) > 1
  ) then
    raise exception '같은 조에 같은 성도가 중복 편성되어 있습니다.';
  end if;

  update public.member_directory md
  set is_active = false,
      left_at = coalesce(md.left_at, v_now)
  where md.church_id = p_church_id
    and md.department_id = p_department_id
    and md.is_active is not false
    and not exists (
      select 1
      from pg_temp.regrouping_assignment_map a
      where a.member_directory_id = md.id
    );

  for v_assignment in select * from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb))
  loop
    v_client_group_id := nullif(v_assignment->>'group_id', '');
    v_group_id := null;
    v_group_name := null;

    if v_client_group_id is not null then
      select gm.group_id, gm.group_name
      into v_group_id, v_group_name
      from pg_temp.regrouping_group_map gm
      where gm.client_group_id = v_client_group_id
         or gm.group_id::text = v_client_group_id
      limit 1;
    end if;

    v_member_directory_id := null;
    if public.phase3_is_uuid(nullif(v_assignment->>'id', '')) then
      v_member_directory_id := (v_assignment->>'id')::uuid;
    end if;

    v_reusable_member_directory_id := null;
    if v_member_directory_id is not null then
      select md.id
      into v_reusable_member_directory_id
      from public.member_directory md
      where md.church_id = p_church_id
        and md.department_id = p_department_id
        and md.id <> v_member_directory_id
        and md.full_name = nullif(btrim(v_assignment->>'full_name'), '')
        and coalesce(public.phase2_normalize_phone(md.phone), '') = coalesce(public.phase2_normalize_phone(v_assignment->>'phone'), '')
        and coalesce(nullif(btrim(md.group_name), ''), '') = coalesce(v_group_name, '')
      order by
        case when md.is_active is not false then 0 else 1 end,
        md.created_at desc nulls last
      limit 1;

      if v_reusable_member_directory_id is not null then
        update public.member_directory
        set is_active = false,
            left_at = coalesce(left_at, v_now)
        where id = v_member_directory_id;

        v_member_directory_id := v_reusable_member_directory_id;
      end if;
    end if;

    if v_member_directory_id is not null then
      select *
      into v_existing_member
      from public.member_directory
      where id = v_member_directory_id;

      if found
        and v_existing_member.church_id = p_church_id
        and v_existing_member.department_id = p_department_id
      then
        v_role_in_group := coalesce(nullif(v_assignment->>'role_in_group', ''), 'member');

        if v_existing_member.is_active is not false
        and coalesce(nullif(btrim(v_existing_member.group_name), ''), '') = coalesce(v_group_name, '')
        and coalesce(v_existing_member.role_in_group, 'member') = v_role_in_group
        then
          member_directory_id := v_existing_member.id;
          return next;
          continue;
        end if;

        update public.member_directory
        set department_id = p_department_id,
            group_name = v_group_name,
            role_in_group = v_role_in_group,
            is_active = true,
            left_at = null
        where id = v_existing_member.id
        returning * into v_saved;

        member_directory_id := v_saved.id;
        return next;
        continue;
      end if;
    end if;

    v_saved := public.upsert_member_person_membership(
      v_member_directory_id,
      p_church_id,
      p_department_id,
      nullif(btrim(v_assignment->>'full_name'), ''),
      public.phase2_normalize_phone(v_assignment->>'phone'),
      v_group_name,
      coalesce(nullif(v_assignment->>'role_in_group', ''), 'member'),
      nullif(v_assignment->>'family_name', ''),
      nullif(v_assignment->>'spouse_name', ''),
      nullif(v_assignment->>'children_info', ''),
      case when nullif(v_assignment->>'birth_date', '') is not null then (v_assignment->>'birth_date')::date else null end,
      case when nullif(v_assignment->>'wedding_anniversary', '') is not null then (v_assignment->>'wedding_anniversary')::date else null end,
      nullif(v_assignment->>'notes', ''),
      nullif(v_assignment->>'avatar_url', ''),
      case when public.phase3_is_uuid(nullif(v_assignment->>'profile_id', '')) then (v_assignment->>'profile_id')::uuid else null end,
      case when public.phase3_is_uuid(nullif(coalesce(v_assignment->>'phase2_person_id', v_assignment->>'person_id'), ''))
        then nullif(coalesce(v_assignment->>'phase2_person_id', v_assignment->>'person_id'), '')::uuid
        else null
      end,
      true
    );

    member_directory_id := v_saved.id;
    return next;
  end loop;
end;
$$;

grant execute on function public.save_regrouping_memberships(
  uuid,
  uuid,
  jsonb,
  jsonb
) to authenticated, service_role;
