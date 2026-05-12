-- Phase 3 person-department lifecycle RPC fix:
-- During restore, keep multiple different groups, but collapse duplicate active
-- memberships for the same person/department/group down to one canonical row,
-- prefer already-active legacy directory rows, then mirror that status back to
-- legacy group_members.

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
  v_has_active_group_memberships boolean := false;
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

    with ranked_active_group_memberships as (
      select
        m.id,
        row_number() over (
          partition by m.group_id
          order by
            (md.is_active is true) desc,
            m.starts_at desc nulls last,
            m.updated_at desc nulls last,
            m.created_at desc
        ) as active_rank
      from public.memberships
      left join public.group_members gm on gm.id = m.legacy_group_member_id
      left join public.member_directory md
        on md.id = coalesce(m.legacy_member_directory_id, gm.member_directory_id)
      where m.person_id = p_person_id
        and m.church_id = p_church_id
        and m.department_id = p_department_id
        and m.status = 'active'
        and m.group_id is not null
    )
    update public.memberships m
    set status = 'inactive',
        ends_at = coalesce(m.ends_at, v_now),
        updated_at = v_now
    from ranked_active_group_memberships ranked
    where m.id = ranked.id
      and ranked.active_rank > 1;

    update public.group_members gm
    set is_active = false
    where gm.id in (
      select m.legacy_group_member_id
      from public.memberships m
      where m.person_id = p_person_id
        and m.church_id = p_church_id
        and m.department_id = p_department_id
        and m.status <> 'active'
        and m.legacy_group_member_id is not null
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

    select exists (
      select 1
      from public.memberships m
      where m.person_id = p_person_id
        and m.church_id = p_church_id
        and m.department_id = p_department_id
        and m.status = 'active'
        and m.group_id is not null
    )
    into v_has_active_group_memberships;

    -- Keep non-canonical legacy rows inactive, but do not update is_active=false
    -- here. Updating that column fires legacy sync triggers and can revert
    -- restored memberships back to inactive.
    update public.member_directory md
    set group_name = null
    where md.church_id = p_church_id
      and md.department_id = p_department_id
      and md.is_active = false
      and md.group_name is not null
      and exists (
        select 1
        from public.member_profiles mp
        where mp.person_id = p_person_id
          and mp.member_directory_id = md.id
      );

    update public.member_directory md
    set is_active = true,
        left_at = null,
        department_id = canonical.department_id,
        group_name = canonical.group_name,
        role_in_group = coalesce(canonical.role, md.role_in_group, 'member')
    from (
      select distinct on (m.group_id)
        coalesce(
          m.legacy_member_directory_id,
          gm.member_directory_id,
          mp.member_directory_id
        ) as resolved_member_directory_id,
        m.department_id,
        g.name as group_name,
        m.role
      from public.memberships m
      join public.groups g on g.id = m.group_id
      left join public.group_members gm on gm.id = m.legacy_group_member_id
      left join public.member_profiles mp
        on mp.person_id = m.person_id
       and mp.member_directory_id is not null
      left join public.member_directory md_canonical
        on md_canonical.id = coalesce(
          m.legacy_member_directory_id,
          gm.member_directory_id,
          mp.member_directory_id
        )
      where m.person_id = p_person_id
        and m.church_id = p_church_id
        and m.department_id = p_department_id
        and m.status = 'active'
        and m.group_id is not null
        and coalesce(m.legacy_member_directory_id, gm.member_directory_id, mp.member_directory_id) is not null
      order by
        m.group_id,
        (md_canonical.is_active is true) desc,
        m.starts_at desc nulls last,
        m.updated_at desc nulls last,
        m.created_at desc
    ) canonical
    where md.id = canonical.resolved_member_directory_id;

    if v_has_active_group_memberships = false then
      update public.member_directory md
      set is_active = true,
          left_at = null,
          department_id = p_department_id,
          group_name = null,
          role_in_group = coalesce(md.role_in_group, 'member')
      where md.id = (
        select md2.id
        from public.member_directory md2
        join public.member_profiles mp on mp.member_directory_id = md2.id
        where mp.person_id = p_person_id
          and md2.church_id = p_church_id
          and md2.department_id = p_department_id
        order by md2.left_at desc nulls last, md2.created_at desc
        limit 1
      );
    end if;
  end if;

  return query
  select distinct mp.member_directory_id
  from public.member_profiles mp
  join public.member_directory md on md.id = mp.member_directory_id
  where mp.person_id = p_person_id
    and md.church_id = p_church_id
    and md.department_id = p_department_id
    and md.is_active = true
    and mp.member_directory_id is not null;
end;
$$;

grant execute on function public.set_person_department_active_status(
  uuid,
  uuid,
  uuid,
  boolean
) to authenticated, service_role;
