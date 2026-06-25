-- Restrict high-impact regrouping write RPCs to approved admins/masters.
--
-- The original SECURITY DEFINER implementations are kept as internal helpers so
-- callers keep the same public RPC names while direct authenticated access is
-- gated by church-scoped admin checks.

set check_function_bodies = off;

do $$
begin
  if to_regprocedure('public.move_member_directory_to_group_unchecked(uuid, uuid, uuid, date)') is null then
    if to_regprocedure('public.move_member_directory_to_group(uuid, uuid, uuid, date)') is null then
      raise exception 'move_member_directory_to_group(uuid, uuid, uuid, date) does not exist.';
    end if;

    alter function public.move_member_directory_to_group(uuid, uuid, uuid, date)
      rename to move_member_directory_to_group_unchecked;
  end if;

  if to_regprocedure('public.save_regrouping_memberships_unchecked(uuid, uuid, jsonb, jsonb)') is null then
    if to_regprocedure('public.save_regrouping_memberships(uuid, uuid, jsonb, jsonb)') is null then
      raise exception 'save_regrouping_memberships(uuid, uuid, jsonb, jsonb) does not exist.';
    end if;

    alter function public.save_regrouping_memberships(uuid, uuid, jsonb, jsonb)
      rename to save_regrouping_memberships_unchecked;
  end if;

  if to_regprocedure('public.save_regrouping_memberships_unchecked(uuid, uuid, jsonb, jsonb, date)') is null then
    if to_regprocedure('public.save_regrouping_memberships(uuid, uuid, jsonb, jsonb, date)') is null then
      raise exception 'save_regrouping_memberships(uuid, uuid, jsonb, jsonb, date) does not exist.';
    end if;

    alter function public.save_regrouping_memberships(uuid, uuid, jsonb, jsonb, date)
      rename to save_regrouping_memberships_unchecked;
  end if;
end $$;

create or replace function public.move_member_directory_to_group(
  p_member_directory_id uuid,
  p_source_group_id uuid,
  p_target_group_id uuid,
  p_effective_week_date date
)
returns public.member_directory
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.member_directory%rowtype;
  v_target_group public.groups%rowtype;
begin
  if p_member_directory_id is null then
    raise exception 'member_directory_id is required.';
  end if;

  if p_target_group_id is null then
    raise exception 'target_group_id is required.';
  end if;

  select *
  into v_member
  from public.member_directory
  where id = p_member_directory_id;

  if not found then
    raise exception 'Member directory row % does not exist.', p_member_directory_id;
  end if;

  select *
  into v_target_group
  from public.groups
  where id = p_target_group_id;

  if not found then
    raise exception 'Target group % does not exist.', p_target_group_id;
  end if;

  if v_target_group.church_id <> v_member.church_id
     or v_target_group.department_id <> v_member.department_id then
    raise exception 'Target group belongs to another church or department.';
  end if;

  if not (
    coalesce(auth.role(), '') = 'service_role'
    or public.check_is_master()
    or public.is_admin_approved(v_member.church_id)
  ) then
    raise exception 'not allowed to move member directory group.';
  end if;

  return public.move_member_directory_to_group_unchecked(
    p_member_directory_id,
    p_source_group_id,
    p_target_group_id,
    p_effective_week_date
  );
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
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if not (
    coalesce(auth.role(), '') = 'service_role'
    or public.check_is_master()
    or public.is_admin_approved(p_church_id)
  ) then
    raise exception 'not allowed to save regrouping memberships.';
  end if;

  return query
  select saved.member_directory_id
  from public.save_regrouping_memberships_unchecked(
    p_church_id,
    p_department_id,
    p_groups,
    p_assignments
  ) as saved;
end;
$$;

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
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if not (
    coalesce(auth.role(), '') = 'service_role'
    or public.check_is_master()
    or public.is_admin_approved(p_church_id)
  ) then
    raise exception 'not allowed to save regrouping memberships.';
  end if;

  return query
  select saved.member_directory_id
  from public.save_regrouping_memberships_unchecked(
    p_church_id,
    p_department_id,
    p_groups,
    p_assignments,
    p_effective_week_date
  ) as saved;
end;
$$;

revoke execute on function public.move_member_directory_to_group_unchecked(
  uuid,
  uuid,
  uuid,
  date
) from public, anon, authenticated;

grant execute on function public.move_member_directory_to_group_unchecked(
  uuid,
  uuid,
  uuid,
  date
) to service_role;

revoke execute on function public.save_regrouping_memberships_unchecked(
  uuid,
  uuid,
  jsonb,
  jsonb
) from public, anon, authenticated;

grant execute on function public.save_regrouping_memberships_unchecked(
  uuid,
  uuid,
  jsonb,
  jsonb
) to service_role;

revoke execute on function public.save_regrouping_memberships_unchecked(
  uuid,
  uuid,
  jsonb,
  jsonb,
  date
) from public, anon, authenticated;

grant execute on function public.save_regrouping_memberships_unchecked(
  uuid,
  uuid,
  jsonb,
  jsonb,
  date
) to service_role;

revoke execute on function public.move_member_directory_to_group(
  uuid,
  uuid,
  uuid,
  date
) from public, anon;

grant execute on function public.move_member_directory_to_group(
  uuid,
  uuid,
  uuid,
  date
) to authenticated, service_role;

revoke execute on function public.save_regrouping_memberships(
  uuid,
  uuid,
  jsonb,
  jsonb
) from public, anon;

grant execute on function public.save_regrouping_memberships(
  uuid,
  uuid,
  jsonb,
  jsonb
) to authenticated, service_role;

revoke execute on function public.save_regrouping_memberships(
  uuid,
  uuid,
  jsonb,
  jsonb,
  date
) from public, anon;

grant execute on function public.save_regrouping_memberships(
  uuid,
  uuid,
  jsonb,
  jsonb,
  date
) to authenticated, service_role;
