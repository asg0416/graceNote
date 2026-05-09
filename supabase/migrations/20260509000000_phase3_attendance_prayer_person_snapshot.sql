-- Phase 3 Task 1:
-- Add person-centered snapshot columns to attendance/prayer records while keeping
-- legacy FK columns for compatibility during the write-switch transition.

begin;

alter table public.attendance
  add column if not exists person_id uuid null references public.people(id) on delete set null,
  add column if not exists membership_id uuid null references public.memberships(id) on delete set null,
  add column if not exists recorded_group_id uuid null references public.groups(id) on delete set null,
  add column if not exists recorded_department_id uuid null references public.departments(id) on delete set null;

alter table public.prayer_entries
  add column if not exists person_id uuid null references public.people(id) on delete set null,
  add column if not exists membership_id uuid null references public.memberships(id) on delete set null,
  add column if not exists recorded_group_id uuid null references public.groups(id) on delete set null,
  add column if not exists recorded_department_id uuid null references public.departments(id) on delete set null;

create index if not exists idx_attendance_person_week
  on public.attendance(person_id, week_id)
  where person_id is not null;

create index if not exists idx_attendance_membership_week
  on public.attendance(membership_id, week_id)
  where membership_id is not null;

create index if not exists idx_attendance_recorded_group_week
  on public.attendance(recorded_group_id, week_id)
  where recorded_group_id is not null;

create index if not exists idx_attendance_recorded_department_week
  on public.attendance(recorded_department_id, week_id)
  where recorded_department_id is not null;

create index if not exists idx_prayer_entries_person_week
  on public.prayer_entries(person_id, week_id)
  where person_id is not null;

create index if not exists idx_prayer_entries_membership_week
  on public.prayer_entries(membership_id, week_id)
  where membership_id is not null;

create index if not exists idx_prayer_entries_recorded_group_week
  on public.prayer_entries(recorded_group_id, week_id)
  where recorded_group_id is not null;

create index if not exists idx_prayer_entries_recorded_department_week
  on public.prayer_entries(recorded_department_id, week_id)
  where recorded_department_id is not null;

create or replace function public.phase3_resolve_membership_snapshot(
  p_group_member_id uuid,
  p_directory_member_id uuid,
  p_group_id uuid,
  p_profile_id uuid default null
)
returns table (
  person_id uuid,
  membership_id uuid,
  group_id uuid,
  department_id uuid
)
language sql
stable
set search_path = public
as $$
  with membership_candidates as (
    select
      m.person_id,
      m.id as membership_id,
      m.group_id,
      m.department_id,
      1 as priority,
      m.status,
      m.updated_at
    from public.memberships m
    where p_group_member_id is not null
      and m.legacy_group_member_id = p_group_member_id

    union all

    select
      m.person_id,
      m.id as membership_id,
      m.group_id,
      m.department_id,
      2 as priority,
      m.status,
      m.updated_at
    from public.memberships m
    where p_directory_member_id is not null
      and m.legacy_member_directory_id = p_directory_member_id
      and (p_group_id is null or m.group_id = p_group_id)

    union all

    select
      m.person_id,
      m.id as membership_id,
      m.group_id,
      m.department_id,
      3 as priority,
      m.status,
      m.updated_at
    from public.memberships m
    where p_directory_member_id is not null
      and m.legacy_member_directory_id = p_directory_member_id
  ),
  best_membership as (
    select *
    from membership_candidates
    order by
      priority,
      case status when 'active' then 0 when 'inactive' then 1 else 2 end,
      updated_at desc
    limit 1
  ),
  profile_candidate as (
    select mp.person_id
    from public.member_profiles mp
    where (
      p_directory_member_id is not null
      and mp.member_directory_id = p_directory_member_id
    )
    or (
      p_profile_id is not null
      and mp.profile_id = p_profile_id
    )
    order by mp.updated_at desc
    limit 1
  )
  select
    coalesce(bm.person_id, pc.person_id) as person_id,
    bm.membership_id,
    coalesce(p_group_id, bm.group_id) as group_id,
    coalesce(bm.department_id, g.department_id) as department_id
  from (select 1) seed
  left join best_membership bm on true
  left join profile_candidate pc on true
  left join public.groups g on g.id = coalesce(p_group_id, bm.group_id);
$$;

create or replace function public.phase3_fill_attendance_person_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snapshot record;
begin
  select *
  into v_snapshot
  from public.phase3_resolve_membership_snapshot(
    NEW.group_member_id,
    NEW.directory_member_id,
    NEW.group_id,
    null
  );

  NEW.person_id := coalesce(NEW.person_id, v_snapshot.person_id);
  NEW.membership_id := coalesce(NEW.membership_id, v_snapshot.membership_id);
  NEW.recorded_group_id := coalesce(NEW.recorded_group_id, v_snapshot.group_id, NEW.group_id);
  NEW.recorded_department_id := coalesce(NEW.recorded_department_id, v_snapshot.department_id);

  return NEW;
end;
$$;

create or replace function public.phase3_fill_prayer_person_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snapshot record;
begin
  select *
  into v_snapshot
  from public.phase3_resolve_membership_snapshot(
    null,
    NEW.directory_member_id,
    NEW.group_id,
    NEW.member_id
  );

  NEW.person_id := coalesce(NEW.person_id, v_snapshot.person_id);
  NEW.membership_id := coalesce(NEW.membership_id, v_snapshot.membership_id);
  NEW.recorded_group_id := coalesce(NEW.recorded_group_id, v_snapshot.group_id, NEW.group_id);
  NEW.recorded_department_id := coalesce(NEW.recorded_department_id, v_snapshot.department_id);

  return NEW;
end;
$$;

drop trigger if exists phase3_attendance_person_snapshot on public.attendance;
create trigger phase3_attendance_person_snapshot
before insert or update of group_member_id, directory_member_id, group_id, person_id, membership_id, recorded_group_id, recorded_department_id
on public.attendance
for each row
execute function public.phase3_fill_attendance_person_snapshot();

drop trigger if exists phase3_prayer_person_snapshot on public.prayer_entries;
create trigger phase3_prayer_person_snapshot
before insert or update of directory_member_id, group_id, member_id, person_id, membership_id, recorded_group_id, recorded_department_id
on public.prayer_entries
for each row
execute function public.phase3_fill_prayer_person_snapshot();

with resolved_attendance as (
  select
    a.id,
    r.person_id,
    r.membership_id,
    r.group_id,
    r.department_id
  from public.attendance a
  cross join lateral public.phase3_resolve_membership_snapshot(
    a.group_member_id,
    a.directory_member_id,
    a.group_id,
    null
  ) r
  where a.person_id is null
     or a.membership_id is null
     or a.recorded_group_id is null
     or a.recorded_department_id is null
)
update public.attendance a
set
  person_id = coalesce(a.person_id, r.person_id),
  membership_id = coalesce(a.membership_id, r.membership_id),
  recorded_group_id = coalesce(a.recorded_group_id, r.group_id, a.group_id),
  recorded_department_id = coalesce(a.recorded_department_id, r.department_id)
from resolved_attendance r
where r.id = a.id;

with resolved_prayer_entries as (
  select
    p.id,
    r.person_id,
    r.membership_id,
    r.group_id,
    r.department_id
  from public.prayer_entries p
  cross join lateral public.phase3_resolve_membership_snapshot(
    null,
    p.directory_member_id,
    p.group_id,
    p.member_id
  ) r
  where p.person_id is null
     or p.membership_id is null
     or p.recorded_group_id is null
     or p.recorded_department_id is null
)
update public.prayer_entries p
set
  person_id = coalesce(p.person_id, r.person_id),
  membership_id = coalesce(p.membership_id, r.membership_id),
  recorded_group_id = coalesce(p.recorded_group_id, r.group_id, p.group_id),
  recorded_department_id = coalesce(p.recorded_department_id, r.department_id)
from resolved_prayer_entries r
where r.id = p.id;

comment on column public.attendance.person_id is
  'Phase 3 person snapshot: whose attendance record this is. Legacy IDs remain during transition.';
comment on column public.attendance.membership_id is
  'Phase 3 membership snapshot: which membership context produced this record, when known.';
comment on column public.attendance.recorded_group_id is
  'Group context captured for historical display even if the person later moves groups.';
comment on column public.attendance.recorded_department_id is
  'Department context captured for historical display even if the person later moves departments.';

comment on column public.prayer_entries.person_id is
  'Phase 3 person snapshot: whose prayer entry this is. Legacy IDs remain during transition.';
comment on column public.prayer_entries.membership_id is
  'Phase 3 membership snapshot: which membership context produced this entry, when known.';
comment on column public.prayer_entries.recorded_group_id is
  'Group context captured for historical display even if the person later moves groups.';
comment on column public.prayer_entries.recorded_department_id is
  'Department context captured for historical display even if the person later moves departments.';

commit;
