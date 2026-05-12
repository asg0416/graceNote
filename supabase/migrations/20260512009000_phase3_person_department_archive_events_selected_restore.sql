-- Phase 3 person-department archive events and selected restore:
-- Record a person-in-department archive event, bind archived memberships to
-- that event, and allow restore callers to choose which group memberships to
-- reactivate.

set check_function_bodies = off;

create table if not exists public.person_department_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  church_id uuid not null references public.churches(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  action text not null check (action in ('archive', 'restore')),
  occurred_at timestamp with time zone not null default now(),
  selected_group_ids uuid[],
  restored_from_event_id uuid references public.person_department_lifecycle_events(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb
);

alter table public.person_department_lifecycle_events enable row level security;

alter table public.memberships
  add column if not exists archived_by_event_id uuid references public.person_department_lifecycle_events(id) on delete set null,
  add column if not exists restored_by_event_id uuid references public.person_department_lifecycle_events(id) on delete set null;

create index if not exists idx_person_department_lifecycle_events_lookup
  on public.person_department_lifecycle_events(person_id, church_id, department_id, action, occurred_at desc);

create index if not exists idx_memberships_archived_by_event_id
  on public.memberships(archived_by_event_id)
  where archived_by_event_id is not null;

create index if not exists idx_memberships_restored_by_event_id
  on public.memberships(restored_by_event_id)
  where restored_by_event_id is not null;

drop policy if exists person_department_lifecycle_events_read_same_church
on public.person_department_lifecycle_events;

create policy person_department_lifecycle_events_read_same_church
on public.person_department_lifecycle_events
for select
to authenticated
using (
  public.check_is_master()
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.church_id = person_department_lifecycle_events.church_id
      and p.role = 'admin'
      and p.admin_status = 'approved'
  )
);

create or replace function public.restore_person_department_affiliation(
  p_person_id uuid,
  p_church_id uuid,
  p_department_id uuid,
  p_group_ids uuid[] default null
)
returns table(member_directory_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamp with time zone := now();
  v_archive_event_id uuid;
  v_restore_event_id uuid;
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

  select e.id
  into v_archive_event_id
  from public.person_department_lifecycle_events e
  where e.person_id = p_person_id
    and e.church_id = p_church_id
    and e.department_id = p_department_id
    and e.action = 'archive'
  order by e.occurred_at desc
  limit 1;

  select max(m.ends_at)
  into v_restore_cutoff
  from public.memberships m
  where m.person_id = p_person_id
    and m.church_id = p_church_id
    and m.department_id = p_department_id
    and m.status in ('inactive', 'ended')
    and m.ends_at is not null;

  insert into public.person_department_lifecycle_events (
    person_id,
    church_id,
    department_id,
    action,
    occurred_at,
    selected_group_ids,
    restored_from_event_id,
    metadata
  )
  values (
    p_person_id,
    p_church_id,
    p_department_id,
    'restore',
    v_now,
    p_group_ids,
    v_archive_event_id,
    jsonb_build_object('source', 'restore_person_department_affiliation')
  )
  returning id into v_restore_event_id;

  update public.memberships m
  set status = 'active',
      ends_at = null,
      updated_at = v_now,
      restored_by_event_id = v_restore_event_id
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
      (
        p_group_ids is not null
        and (
          (
            cardinality(coalesce(p_group_ids, '{}'::uuid[])) = 0
            and m.group_id is null
          )
          or m.group_id = any(p_group_ids)
        )
      )
      or (
        p_group_ids is null
        and (
          (
            v_archive_event_id is not null
            and m.archived_by_event_id = v_archive_event_id
          )
          or (
            v_archive_event_id is null
            and (
              v_restore_cutoff is null
              or m.ends_at >= v_restore_cutoff - interval '5 seconds'
            )
          )
        )
      )
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
    from public.memberships m
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
  v_archive_event_id uuid;
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

  if coalesce(p_is_active, true) = true then
    return query
    select *
    from public.restore_person_department_affiliation(
      p_person_id,
      p_church_id,
      p_department_id,
      null::uuid[]
    );
    return;
  end if;

  insert into public.person_department_lifecycle_events (
    person_id,
    church_id,
    department_id,
    action,
    occurred_at,
    metadata
  )
  values (
    p_person_id,
    p_church_id,
    p_department_id,
    'archive',
    v_now,
    jsonb_build_object('source', 'set_person_department_active_status')
  )
  returning id into v_archive_event_id;

  update public.memberships
  set status = 'inactive',
      ends_at = coalesce(ends_at, v_now),
      updated_at = v_now,
      archived_by_event_id = v_archive_event_id,
      restored_by_event_id = null
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

grant execute on function public.restore_person_department_affiliation(
  uuid,
  uuid,
  uuid,
  uuid[]
) to authenticated, service_role;

grant execute on function public.set_person_department_active_status(
  uuid,
  uuid,
  uuid,
  boolean
) to authenticated, service_role;
