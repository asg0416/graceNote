-- Attendance roster snapshots:
-- Store the week+department attendance denominator explicitly so historical
-- reports no longer infer target members from current roster or submitted rows.

begin;

create table if not exists public.attendance_roster_snapshots (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id) on delete restrict,
  department_id uuid not null references public.departments(id) on delete restrict,
  week_id uuid not null references public.weeks(id) on delete restrict,
  status text not null default 'system_generated'
    check (status in ('system_generated', 'admin_adjusted', 'locked')),
  source text not null default 'auto'
    check (source in ('auto', 'manual', 'migration_backfill')),
  generated_at timestamptz not null default now(),
  generated_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid null references auth.users(id) on delete set null,
  note text null,
  unique (department_id, week_id)
);

create table if not exists public.attendance_roster_snapshot_members (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.attendance_roster_snapshots(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete restrict,
  membership_id uuid null references public.memberships(id) on delete set null,
  legacy_member_directory_id uuid null references public.member_directory(id) on delete set null,
  group_id uuid null references public.groups(id) on delete set null,
  role text null,
  display_name text not null,
  group_name text null,
  attendance_status text not null default 'unknown'
    check (attendance_status in ('present', 'late', 'absent', 'unknown')),
  included boolean not null default true,
  source text not null default 'auto_membership'
    check (source in ('auto_membership', 'attendance_snapshot', 'manual_add', 'manual_exclude', 'migration_backfill')),
  reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (snapshot_id, person_id)
);

create table if not exists public.attendance_roster_snapshot_events (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.attendance_roster_snapshots(id) on delete cascade,
  person_id uuid null references public.people(id) on delete set null,
  event_type text not null check (event_type in (
    'snapshot_created',
    'member_added',
    'member_excluded',
    'member_restored',
    'attendance_status_changed',
    'snapshot_locked',
    'snapshot_unlocked'
  )),
  before jsonb null,
  after jsonb null,
  reason text null,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null
);

create index if not exists idx_attendance_roster_snapshots_church_week
  on public.attendance_roster_snapshots(church_id, week_id);

create index if not exists idx_attendance_roster_snapshots_week_department
  on public.attendance_roster_snapshots(week_id, department_id);

create index if not exists idx_attendance_roster_snapshot_members_snapshot_included
  on public.attendance_roster_snapshot_members(snapshot_id, included);

create index if not exists idx_attendance_roster_snapshot_members_group
  on public.attendance_roster_snapshot_members(snapshot_id, group_id);

create index if not exists idx_attendance_roster_snapshot_events_snapshot
  on public.attendance_roster_snapshot_events(snapshot_id, created_at desc);

alter table public.attendance_roster_snapshots enable row level security;
alter table public.attendance_roster_snapshot_members enable row level security;
alter table public.attendance_roster_snapshot_events enable row level security;

drop policy if exists "Attendance roster snapshots select" on public.attendance_roster_snapshots;
create policy "Attendance roster snapshots select"
  on public.attendance_roster_snapshots
  for select
  to authenticated
  using (
    public.check_is_master()
    or public.is_admin_approved(church_id)
    or church_id = public.get_my_church_id()
  );

drop policy if exists "Attendance roster snapshot members select" on public.attendance_roster_snapshot_members;
create policy "Attendance roster snapshot members select"
  on public.attendance_roster_snapshot_members
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.attendance_roster_snapshots s
      where s.id = attendance_roster_snapshot_members.snapshot_id
        and (
          public.check_is_master()
          or public.is_admin_approved(s.church_id)
          or s.church_id = public.get_my_church_id()
        )
    )
  );

drop policy if exists "Attendance roster snapshot events select" on public.attendance_roster_snapshot_events;
create policy "Attendance roster snapshot events select"
  on public.attendance_roster_snapshot_events
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.attendance_roster_snapshots s
      where s.id = attendance_roster_snapshot_events.snapshot_id
        and (
          public.check_is_master()
          or public.is_admin_approved(s.church_id)
          or s.church_id = public.get_my_church_id()
        )
    )
  );

commit;

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
        'week_date', v_week_date
      ),
      auth.uid()
    );
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
  order by
    m.person_id,
    case when m.role = 'leader' then 0 else 1 end,
    case when m.group_id is not null then 0 else 1 end,
    m.starts_at nulls first,
    m.created_at nulls first
  on conflict (snapshot_id, person_id) do nothing;

  return v_snapshot_id;
end;
$$;

create or replace function public.set_attendance_roster_snapshot_member_included(
  p_snapshot_member_id uuid,
  p_included boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot_id uuid;
  v_church_id uuid;
  v_person_id uuid;
  v_before jsonb;
begin
  select sm.snapshot_id, s.church_id, sm.person_id, to_jsonb(sm)
    into v_snapshot_id, v_church_id, v_person_id, v_before
  from public.attendance_roster_snapshot_members sm
  join public.attendance_roster_snapshots s on s.id = sm.snapshot_id
  where sm.id = p_snapshot_member_id;

  if v_snapshot_id is null then
    raise exception 'snapshot member not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_church_id)
  ) then
    raise exception 'not allowed to edit attendance roster snapshot';
  end if;

  update public.attendance_roster_snapshot_members
     set included = p_included,
         source = case when p_included then 'manual_add' else 'manual_exclude' end,
         reason = p_reason,
         updated_at = now()
   where id = p_snapshot_member_id;

  update public.attendance_roster_snapshots
     set status = 'admin_adjusted',
         source = 'manual',
         updated_at = now(),
         updated_by = auth.uid()
   where id = v_snapshot_id
     and status <> 'locked';

  insert into public.attendance_roster_snapshot_events (
    snapshot_id,
    person_id,
    event_type,
    before,
    after,
    reason,
    created_by
  )
  values (
    v_snapshot_id,
    v_person_id,
    case when p_included then 'member_restored' else 'member_excluded' end,
    v_before,
    jsonb_build_object('included', p_included),
    p_reason,
    auth.uid()
  );
end;
$$;

create or replace function public.set_attendance_roster_snapshot_member_status(
  p_snapshot_member_id uuid,
  p_attendance_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot_id uuid;
  v_church_id uuid;
  v_person_id uuid;
  v_before jsonb;
begin
  if p_attendance_status not in ('present', 'late', 'absent', 'unknown') then
    raise exception 'invalid attendance status';
  end if;

  select sm.snapshot_id, s.church_id, sm.person_id, to_jsonb(sm)
    into v_snapshot_id, v_church_id, v_person_id, v_before
  from public.attendance_roster_snapshot_members sm
  join public.attendance_roster_snapshots s on s.id = sm.snapshot_id
  where sm.id = p_snapshot_member_id;

  if v_snapshot_id is null then
    raise exception 'snapshot member not found';
  end if;

  if not (
    current_user in ('postgres', 'service_role')
    or public.check_is_master()
    or public.is_admin_approved(v_church_id)
  ) then
    raise exception 'not allowed to edit attendance roster snapshot';
  end if;

  update public.attendance_roster_snapshot_members
     set attendance_status = p_attendance_status,
         reason = p_reason,
         updated_at = now()
   where id = p_snapshot_member_id;

  update public.attendance_roster_snapshots
     set status = 'admin_adjusted',
         source = 'manual',
         updated_at = now(),
         updated_by = auth.uid()
   where id = v_snapshot_id
     and status <> 'locked';

  insert into public.attendance_roster_snapshot_events (
    snapshot_id,
    person_id,
    event_type,
    before,
    after,
    reason,
    created_by
  )
  values (
    v_snapshot_id,
    v_person_id,
    'attendance_status_changed',
    v_before,
    jsonb_build_object('attendance_status', p_attendance_status),
    p_reason,
    auth.uid()
  );
end;
$$;

grant execute on function public.ensure_attendance_roster_snapshot(uuid, uuid) to authenticated, service_role;
grant execute on function public.set_attendance_roster_snapshot_member_included(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.set_attendance_roster_snapshot_member_status(uuid, text, text) to authenticated, service_role;
