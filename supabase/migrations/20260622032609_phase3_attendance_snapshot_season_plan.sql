-- Make attendance roster snapshot generation season-plan aware.
--
-- The admin attendance page now calculates denominators from regrouping season
-- plans. This migration moves the DB snapshot generator to the same source of
-- truth so that snapshot rows do not drift back to live memberships when an
-- admin opens a week or bulk-loads missing rosters.

set check_function_bodies = off;

create or replace function public.ensure_attendance_roster_snapshot(
  p_department_id uuid,
  p_week_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot_id uuid;
  v_week_date date;
  v_church_id uuid;
  v_season_id uuid;
  v_created boolean := false;
begin
  select w.week_date, d.church_id
    into v_week_date, v_church_id
  from public.weeks w
  join public.departments d on d.id = p_department_id
  where w.id = p_week_id;

  if v_week_date is null or v_church_id is null then
    raise exception 'week or department not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_church_id)
    or v_church_id = public.get_my_church_id()
  ) then
    raise exception 'not allowed to read attendance roster snapshot';
  end if;

  select s.id
    into v_season_id
  from public.regrouping_seasons s
  where s.church_id = v_church_id
    and s.department_id = p_department_id
    and s.status in ('applied', 'archived')
    and s.effective_week_date <= v_week_date
    and (s.end_week_date is null or s.end_week_date >= v_week_date)
  order by s.effective_week_date desc, s.updated_at desc, s.created_at desc
  limit 1;

  insert into public.attendance_roster_snapshots (
    church_id,
    department_id,
    week_id,
    status,
    source,
    generated_by,
    updated_by
  )
  values (
    v_church_id,
    p_department_id,
    p_week_id,
    'system_generated',
    'auto',
    auth.uid(),
    auth.uid()
  )
  on conflict (department_id, week_id) do update
    set updated_at = public.attendance_roster_snapshots.updated_at
  returning id, (xmax = 0) into v_snapshot_id, v_created;

  if v_created then
    insert into public.attendance_roster_snapshot_events (
      snapshot_id,
      event_type,
      after,
      created_by
    )
    values (
      v_snapshot_id,
      'snapshot_created',
      jsonb_build_object(
        'department_id', p_department_id,
        'week_id', p_week_id,
        'week_date', v_week_date,
        'season_id', v_season_id
      ),
      auth.uid()
    );
  end if;

  if v_season_id is not null then
    with plan_roster as (
      select distinct on (rpa.person_id)
        rpa.person_id,
        rpa.source_membership_id as membership_id,
        rpa.source_member_directory_id as legacy_member_directory_id,
        rpg.source_group_id as group_id,
        rpa.role_in_group as role,
        coalesce(
          nullif(md.full_name, ''),
          nullif(mp.full_name, ''),
          nullif(p.display_name, ''),
          '이름 없음'
        ) as display_name,
        rpg.name as group_name
      from public.regrouping_plan_assignments rpa
      join public.regrouping_plan_groups rpg
        on rpg.id = rpa.plan_group_id
       and rpg.season_id = rpa.season_id
      join public.regrouping_seasons s
        on s.id = rpa.season_id
      join public.people p
        on p.id = rpa.person_id
      left join public.member_directory md
        on md.id = rpa.source_member_directory_id
      left join lateral (
        select mp2.*
        from public.member_profiles mp2
        where mp2.person_id = rpa.person_id
        order by
          case when mp2.member_directory_id = rpa.source_member_directory_id then 0 else 1 end,
          mp2.updated_at desc nulls last,
          mp2.created_at desc
        limit 1
      ) mp on true
      where rpa.season_id = v_season_id
        and rpa.plan_group_id is not null
        and coalesce(rpg.starts_week_date, s.effective_week_date) <= v_week_date
        and (
          coalesce(rpg.ends_week_date, s.end_week_date) is null
          or coalesce(rpg.ends_week_date, s.end_week_date) >= v_week_date
        )
        and coalesce(rpa.starts_week_date, rpg.starts_week_date, s.effective_week_date) <= v_week_date
        and (
          coalesce(rpa.ends_week_date, rpg.ends_week_date, s.end_week_date) is null
          or coalesce(rpa.ends_week_date, rpg.ends_week_date, s.end_week_date) >= v_week_date
        )
      order by
        rpa.person_id,
        case when rpa.role_in_group = 'leader' then 0 else 1 end,
        rpg.sort_order nulls last,
        rpa.sort_order nulls last,
        rpa.updated_at desc
    )
    delete from public.attendance_roster_snapshot_members sm
    where sm.snapshot_id = v_snapshot_id
      and sm.source = 'auto_membership'
      and sm.attendance_status = 'unknown'
      and (sm.reason is null or sm.reason in ('bulk load missing group rosters', 'load group roster'))
      and not exists (
        select 1
        from plan_roster pr
        where pr.person_id = sm.person_id
      );

    insert into public.attendance_roster_snapshot_members (
      snapshot_id,
      person_id,
      membership_id,
      legacy_member_directory_id,
      group_id,
      role,
      display_name,
      group_name,
      attendance_status,
      included,
      source,
      reason
    )
    with plan_roster as (
      select distinct on (rpa.person_id)
        rpa.person_id,
        rpa.source_membership_id as membership_id,
        rpa.source_member_directory_id as legacy_member_directory_id,
        rpg.source_group_id as group_id,
        rpa.role_in_group as role,
        coalesce(
          nullif(md.full_name, ''),
          nullif(mp.full_name, ''),
          nullif(p.display_name, ''),
          '이름 없음'
        ) as display_name,
        rpg.name as group_name
      from public.regrouping_plan_assignments rpa
      join public.regrouping_plan_groups rpg
        on rpg.id = rpa.plan_group_id
       and rpg.season_id = rpa.season_id
      join public.regrouping_seasons s
        on s.id = rpa.season_id
      join public.people p
        on p.id = rpa.person_id
      left join public.member_directory md
        on md.id = rpa.source_member_directory_id
      left join lateral (
        select mp2.*
        from public.member_profiles mp2
        where mp2.person_id = rpa.person_id
        order by
          case when mp2.member_directory_id = rpa.source_member_directory_id then 0 else 1 end,
          mp2.updated_at desc nulls last,
          mp2.created_at desc
        limit 1
      ) mp on true
      where rpa.season_id = v_season_id
        and rpa.plan_group_id is not null
        and coalesce(rpg.starts_week_date, s.effective_week_date) <= v_week_date
        and (
          coalesce(rpg.ends_week_date, s.end_week_date) is null
          or coalesce(rpg.ends_week_date, s.end_week_date) >= v_week_date
        )
        and coalesce(rpa.starts_week_date, rpg.starts_week_date, s.effective_week_date) <= v_week_date
        and (
          coalesce(rpa.ends_week_date, rpg.ends_week_date, s.end_week_date) is null
          or coalesce(rpa.ends_week_date, rpg.ends_week_date, s.end_week_date) >= v_week_date
        )
      order by
        rpa.person_id,
        case when rpa.role_in_group = 'leader' then 0 else 1 end,
        rpg.sort_order nulls last,
        rpa.sort_order nulls last,
        rpa.updated_at desc
    )
    select
      v_snapshot_id,
      pr.person_id,
      pr.membership_id,
      pr.legacy_member_directory_id,
      pr.group_id,
      pr.role,
      pr.display_name,
      pr.group_name,
      'unknown',
      true,
      'auto_membership',
      null
    from plan_roster pr
    on conflict (snapshot_id, person_id) do update
      set
        membership_id = excluded.membership_id,
        legacy_member_directory_id = coalesce(excluded.legacy_member_directory_id, attendance_roster_snapshot_members.legacy_member_directory_id),
        group_id = excluded.group_id,
        role = excluded.role,
        display_name = coalesce(nullif(excluded.display_name, ''), attendance_roster_snapshot_members.display_name),
        group_name = coalesce(nullif(excluded.group_name, ''), attendance_roster_snapshot_members.group_name),
        included = true,
        source = attendance_roster_snapshot_members.source,
        reason = case
          when attendance_roster_snapshot_members.source = 'auto_membership' then null
          else attendance_roster_snapshot_members.reason
        end,
        updated_at = now()
      where (
        (
          attendance_roster_snapshot_members.source = 'auto_membership'
          and attendance_roster_snapshot_members.attendance_status = 'unknown'
          and (
            attendance_roster_snapshot_members.reason is null
            or attendance_roster_snapshot_members.reason in ('bulk load missing group rosters', 'load group roster')
          )
        )
        or attendance_roster_snapshot_members.source = 'attendance_snapshot'
      );
  else
    insert into public.attendance_roster_snapshot_members (
      snapshot_id,
      person_id,
      membership_id,
      legacy_member_directory_id,
      group_id,
      role,
      display_name,
      group_name,
      attendance_status,
      included,
      source
    )
    select distinct on (m.person_id)
      v_snapshot_id,
      m.person_id,
      m.id,
      m.legacy_member_directory_id,
      m.group_id,
      m.role,
      coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), nullif(p.display_name, ''), '이름 없음') as display_name,
      g.name as group_name,
      'unknown',
      true,
      'auto_membership'
    from public.memberships m
    join public.people p on p.id = m.person_id
    left join public.member_directory md on md.id = m.legacy_member_directory_id
    left join public.member_profiles mp on mp.person_id = m.person_id
    left join public.groups g on g.id = m.group_id
    where m.department_id = p_department_id
      and m.church_id = v_church_id
      and m.status = 'active'
      and (m.starts_at is null or m.starts_at::date <= v_week_date)
      and (m.ends_at is null or m.ends_at::date >= v_week_date)
      and (
        g.id is null
        or (
          g.department_id = p_department_id
          and (g.active_from is null or g.active_from::date <= v_week_date)
          and (g.ended_at is null or g.ended_at::date >= v_week_date)
        )
      )
    order by
      m.person_id,
      case when m.role = 'leader' then 0 else 1 end,
      case when m.group_id is not null then 0 else 1 end,
      m.starts_at nulls first,
      m.created_at nulls first
    on conflict (snapshot_id, person_id) do nothing;
  end if;

  insert into public.attendance_roster_snapshot_members (
    snapshot_id,
    person_id,
    membership_id,
    legacy_member_directory_id,
    group_id,
    role,
    display_name,
    group_name,
    attendance_status,
    included,
    source
  )
  select distinct on (coalesce(a.person_id, md.person_id, mp.person_id))
    v_snapshot_id,
    coalesce(a.person_id, md.person_id, mp.person_id) as person_id,
    coalesce(a.membership_id, m.id) as membership_id,
    a.directory_member_id,
    coalesce(a.recorded_group_id, a.group_id, g.id),
    coalesce(m.role, md.role_in_group, 'member') as role,
    coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), p.display_name, '이름 없음') as display_name,
    coalesce(g.name, md.group_name) as group_name,
    case
      when a.status in ('present', 'late', 'absent') then a.status
      else 'unknown'
    end as attendance_status,
    true,
    'attendance_snapshot'
  from public.attendance a
  join public.groups g on g.id = coalesce(a.recorded_group_id, a.group_id)
  left join public.member_directory md on md.id = a.directory_member_id
  left join public.member_profiles mp on mp.member_directory_id = a.directory_member_id
  left join public.people p on p.id = coalesce(a.person_id, md.person_id, mp.person_id)
  left join public.memberships m
    on m.person_id = coalesce(a.person_id, md.person_id, mp.person_id)
   and m.department_id = p_department_id
   and m.church_id = v_church_id
   and (
     m.id = a.membership_id
     or m.legacy_member_directory_id = a.directory_member_id
     or m.group_id = coalesce(a.recorded_group_id, a.group_id, g.id)
   )
  where a.week_id = p_week_id
    and g.department_id = p_department_id
    and coalesce(a.person_id, md.person_id, mp.person_id) is not null
  order by
    coalesce(a.person_id, md.person_id, mp.person_id),
    case when a.status in ('present', 'late') then 0 else 1 end,
    a.updated_at desc nulls last,
    a.created_at desc nulls last
  on conflict (snapshot_id, person_id) do update
    set
      membership_id = coalesce(excluded.membership_id, attendance_roster_snapshot_members.membership_id),
      legacy_member_directory_id = coalesce(excluded.legacy_member_directory_id, attendance_roster_snapshot_members.legacy_member_directory_id),
      group_id = case
        when v_season_id is not null then attendance_roster_snapshot_members.group_id
        else coalesce(excluded.group_id, attendance_roster_snapshot_members.group_id)
      end,
      role = case
        when v_season_id is not null then coalesce(attendance_roster_snapshot_members.role, excluded.role)
        else coalesce(excluded.role, attendance_roster_snapshot_members.role)
      end,
      display_name = coalesce(nullif(excluded.display_name, ''), attendance_roster_snapshot_members.display_name),
      group_name = case
        when v_season_id is not null then attendance_roster_snapshot_members.group_name
        else coalesce(nullif(excluded.group_name, ''), attendance_roster_snapshot_members.group_name)
      end,
      attendance_status = excluded.attendance_status,
      included = true,
      source = 'attendance_snapshot'
    where attendance_roster_snapshot_members.source = 'auto_membership'
      and attendance_roster_snapshot_members.attendance_status = 'unknown'
      and (
        attendance_roster_snapshot_members.reason is null
        or attendance_roster_snapshot_members.reason in ('bulk load missing group rosters', 'load group roster')
      );

  return v_snapshot_id;
end;
$$;

grant execute on function public.ensure_attendance_roster_snapshot(uuid, uuid) to authenticated, service_role;

create or replace function public.load_missing_group_rosters_into_attendance_snapshot(
  p_snapshot_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot public.attendance_roster_snapshots%rowtype;
  v_before integer := 0;
  v_after integer := 0;
begin
  select * into v_snapshot
  from public.attendance_roster_snapshots
  where id = p_snapshot_id;

  if v_snapshot.id is null then
    raise exception 'snapshot not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_snapshot.church_id)
  ) then
    raise exception 'not allowed to edit attendance roster snapshot';
  end if;

  if v_snapshot.status = 'locked' then
    raise exception 'snapshot is locked';
  end if;

  select count(*)::integer
    into v_before
  from public.attendance_roster_snapshot_members
  where snapshot_id = p_snapshot_id
    and included = true;

  perform public.ensure_attendance_roster_snapshot(
    v_snapshot.department_id,
    v_snapshot.week_id
  );

  select count(*)::integer
    into v_after
  from public.attendance_roster_snapshot_members
  where snapshot_id = p_snapshot_id
    and included = true;

  if v_after > v_before then
    update public.attendance_roster_snapshots
       set status = 'admin_adjusted',
           source = 'manual',
           updated_at = now(),
           updated_by = auth.uid()
     where id = p_snapshot_id;

    insert into public.attendance_roster_snapshot_events (
      snapshot_id,
      event_type,
      after,
      reason,
      created_by
    )
    values (
      p_snapshot_id,
      'member_added',
      jsonb_build_object('count', v_after - v_before, 'mode', 'season_plan_missing_rosters'),
      'season plan missing roster sync',
      auth.uid()
    );
  end if;

  return greatest(v_after - v_before, 0);
end;
$$;

grant execute on function public.load_missing_group_rosters_into_attendance_snapshot(uuid)
  to authenticated, service_role;

create or replace function public.load_group_roster_into_attendance_snapshot(
  p_snapshot_id uuid,
  p_group_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot public.attendance_roster_snapshots%rowtype;
  v_group public.groups%rowtype;
  v_week_date date;
  v_season_id uuid;
  v_before integer := 0;
  v_after integer := 0;
  v_inserted integer := 0;
begin
  select * into v_snapshot
  from public.attendance_roster_snapshots
  where id = p_snapshot_id;

  if v_snapshot.id is null then
    raise exception 'snapshot not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_snapshot.church_id)
  ) then
    raise exception 'not allowed to edit attendance roster snapshot';
  end if;

  if v_snapshot.status = 'locked' then
    raise exception 'snapshot is locked';
  end if;

  select * into v_group
  from public.groups
  where id = p_group_id
    and church_id = v_snapshot.church_id
    and department_id = v_snapshot.department_id;

  if v_group.id is null then
    raise exception 'group not found in snapshot department';
  end if;

  select w.week_date
    into v_week_date
  from public.weeks w
  where w.id = v_snapshot.week_id;

  select s.id
    into v_season_id
  from public.regrouping_seasons s
  where s.church_id = v_snapshot.church_id
    and s.department_id = v_snapshot.department_id
    and s.status in ('applied', 'archived')
    and s.effective_week_date <= v_week_date
    and (s.end_week_date is null or s.end_week_date >= v_week_date)
  order by s.effective_week_date desc, s.updated_at desc, s.created_at desc
  limit 1;

  if v_season_id is not null then
    select count(*)::integer
      into v_before
    from public.attendance_roster_snapshot_members
    where snapshot_id = p_snapshot_id
      and group_id = p_group_id
      and included = true;

    perform public.ensure_attendance_roster_snapshot(
      v_snapshot.department_id,
      v_snapshot.week_id
    );

    select count(*)::integer
      into v_after
    from public.attendance_roster_snapshot_members
    where snapshot_id = p_snapshot_id
      and group_id = p_group_id
      and included = true;

    return greatest(v_after - v_before, 0);
  end if;

  insert into public.attendance_roster_snapshot_members (
    snapshot_id,
    person_id,
    membership_id,
    legacy_member_directory_id,
    group_id,
    role,
    display_name,
    group_name,
    attendance_status,
    included,
    source,
    reason
  )
  select distinct on (m.person_id)
    p_snapshot_id,
    m.person_id,
    m.id,
    m.legacy_member_directory_id,
    p_group_id,
    m.role,
    coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), nullif(p.display_name, ''), '이름 없음'),
    v_group.name,
    'unknown',
    true,
    'auto_membership',
    'load group roster'
  from public.memberships m
  join public.people p on p.id = m.person_id
  left join public.member_directory md on md.id = m.legacy_member_directory_id
  left join public.member_profiles mp on mp.person_id = m.person_id
  where m.church_id = v_snapshot.church_id
    and m.department_id = v_snapshot.department_id
    and m.group_id = p_group_id
    and m.status = 'active'
    and (m.starts_at is null or m.starts_at::date <= v_week_date)
    and (m.ends_at is null or m.ends_at::date >= v_week_date)
    and (v_group.active_from is null or v_group.active_from::date <= v_week_date)
    and (v_group.ended_at is null or v_group.ended_at::date >= v_week_date)
  order by
    m.person_id,
    case when m.role = 'leader' then 0 else 1 end,
    m.updated_at desc nulls last
  on conflict (snapshot_id, person_id) do update
    set included = true,
        membership_id = excluded.membership_id,
        legacy_member_directory_id = coalesce(excluded.legacy_member_directory_id, attendance_roster_snapshot_members.legacy_member_directory_id),
        group_id = excluded.group_id,
        role = excluded.role,
        group_name = excluded.group_name,
        source = excluded.source,
        reason = excluded.reason,
        updated_at = now();

  get diagnostics v_inserted = row_count;

  update public.attendance_roster_snapshots
     set status = 'admin_adjusted',
         source = 'manual',
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_snapshot_id;

  return v_inserted;
end;
$$;

grant execute on function public.load_group_roster_into_attendance_snapshot(uuid, uuid)
  to authenticated, service_role;
