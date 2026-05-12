-- Phase 3 person-department lifecycle RPC:
-- Treat archive/restore as a person-in-department operation instead of a
-- single legacy member_directory row operation.

set check_function_bodies = off;

create or replace function public.set_person_department_active_status(
  p_person_id uuid,
  p_church_id uuid,
  p_department_id uuid,
  p_is_active boolean
)
returns table(member_directory_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamp with time zone := now();
  v_restore_cutoff timestamp with time zone;
begin
  if p_person_id is null then
    raise exception 'person_id is required.';
  end if;

  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if coalesce(p_is_active, true) = false then
    update public.memberships
    set status = 'inactive',
        ends_at = coalesce(ends_at, v_now),
        updated_at = v_now
    where person_id = p_person_id
      and church_id = p_church_id
      and department_id = p_department_id
      and status = 'active';

    update public.group_members gm
    set is_active = false
    where gm.id in (
      select m.legacy_group_member_id
      from public.memberships m
      where m.person_id = p_person_id
        and m.church_id = p_church_id
        and m.department_id = p_department_id
        and m.legacy_group_member_id is not null
    );

    update public.member_directory md
    set is_active = false,
        left_at = coalesce(left_at, v_now)
    where md.church_id = p_church_id
      and md.department_id = p_department_id
      and exists (
        select 1
        from public.member_profiles mp
        where mp.person_id = p_person_id
          and mp.member_directory_id = md.id
      );
  else
    select max(ends_at)
    into v_restore_cutoff
    from public.memberships
    where person_id = p_person_id
      and church_id = p_church_id
      and department_id = p_department_id
      and status in ('inactive', 'ended')
      and ends_at is not null;

    update public.memberships m
    set status = 'active',
        ends_at = null,
        updated_at = v_now
    where m.person_id = p_person_id
      and m.church_id = p_church_id
      and m.department_id = p_department_id
      and m.status in ('inactive', 'ended')
      and (
        m.group_id is null
        or exists (
        select 1
        from public.groups g
        where g.id = m.group_id
          and g.is_active = true
        )
      )
      and (
        v_restore_cutoff is null
        or m.ends_at >= v_restore_cutoff - interval '5 seconds'
      );

    update public.group_members gm
    set is_active = true
    where gm.id in (
      select m.legacy_group_member_id
      from public.memberships m
      where m.person_id = p_person_id
        and m.church_id = p_church_id
        and m.department_id = p_department_id
        and m.status = 'active'
        and m.legacy_group_member_id is not null
    );

    update public.member_directory md
    set is_active = true,
        left_at = null
    where md.church_id = p_church_id
      and md.department_id = p_department_id
      and exists (
        select 1
        from public.member_profiles mp
        where mp.person_id = p_person_id
          and mp.member_directory_id = md.id
      );

    update public.member_directory md
    set department_id = coalesce(active_membership.department_id, md.department_id),
        group_name = coalesce(active_membership.group_name, md.group_name),
        role_in_group = coalesce(active_membership.role, md.role_in_group, 'member')
    from (
      select distinct on (m.legacy_member_directory_id)
        m.legacy_member_directory_id,
        m.department_id,
        g.name as group_name,
        m.role
      from public.memberships m
      join public.groups g on g.id = m.group_id
      where m.person_id = p_person_id
        and m.church_id = p_church_id
        and m.department_id = p_department_id
        and m.status = 'active'
        and m.legacy_member_directory_id is not null
      order by m.legacy_member_directory_id, m.updated_at desc nulls last, m.starts_at desc nulls last
    ) active_membership
    where md.id = active_membership.legacy_member_directory_id;
  end if;

  return query
  select distinct mp.member_directory_id
  from public.member_profiles mp
  join public.member_directory md on md.id = mp.member_directory_id
  where mp.person_id = p_person_id
    and md.church_id = p_church_id
    and md.department_id = p_department_id
    and mp.member_directory_id is not null;
end;
$$;

grant execute on function public.set_person_department_active_status(
  uuid,
  uuid,
  uuid,
  boolean
) to authenticated, service_role;
