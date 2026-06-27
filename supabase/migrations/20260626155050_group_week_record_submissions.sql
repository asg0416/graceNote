create table if not exists public.group_week_record_submissions (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  week_id uuid not null references public.weeks(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  attendance_submitted_at timestamptz null,
  attendance_submitted_by uuid null references public.profiles(id) on delete set null,
  attendance_source text null check (attendance_source in ('app', 'admin_web', 'backfill', 'manual')),
  prayer_submitted_at timestamptz null,
  prayer_submitted_by uuid null references public.profiles(id) on delete set null,
  prayer_source text null check (prayer_source in ('app', 'admin_web', 'backfill', 'manual')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_week_record_submissions_week_group_unique unique (week_id, group_id),
  constraint group_week_record_submissions_has_marker check (
    attendance_submitted_at is not null
    or prayer_submitted_at is not null
  ),
  constraint group_week_record_submissions_attendance_source_required check (
    attendance_submitted_at is null
    or attendance_source is not null
  ),
  constraint group_week_record_submissions_prayer_source_required check (
    prayer_submitted_at is null
    or prayer_source is not null
  )
);

create index if not exists idx_group_week_record_submissions_department_week
  on public.group_week_record_submissions(department_id, week_id);

create index if not exists idx_group_week_record_submissions_group_week
  on public.group_week_record_submissions(group_id, week_id);

create index if not exists idx_group_week_record_submissions_church_week
  on public.group_week_record_submissions(church_id, week_id);

do $$
begin
  if not exists (
    select 1
    from pg_proc
    where proname = 'set_updated_at'
      and pronamespace = 'public'::regnamespace
  ) then
    execute $func$
      create function public.set_updated_at()
      returns trigger language plpgsql as $inner$
      begin
        new.updated_at = now();
        return new;
      end;
      $inner$
    $func$;
  end if;
end;
$$;

drop trigger if exists group_week_record_submissions_set_updated_at
  on public.group_week_record_submissions;

create trigger group_week_record_submissions_set_updated_at
  before update on public.group_week_record_submissions
  for each row execute function public.set_updated_at();

create or replace function public.set_group_week_record_submission_audit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  current_profile_id uuid := auth.uid();
  attendance_changed boolean := false;
  prayer_changed boolean := false;
begin
  if new.attendance_submitted_at is null then
    new.attendance_submitted_by = null;
    new.attendance_source = null;
  elsif new.attendance_source is null then
    new.attendance_source = 'app';
  end if;

  if new.prayer_submitted_at is null then
    new.prayer_submitted_by = null;
    new.prayer_source = null;
  elsif new.prayer_source is null then
    new.prayer_source = 'app';
  end if;

  if tg_op = 'INSERT' then
    attendance_changed := true;
    prayer_changed := true;
  else
    attendance_changed :=
      new.attendance_submitted_at is distinct from old.attendance_submitted_at
      or new.attendance_source is distinct from old.attendance_source
      or new.attendance_submitted_by is distinct from old.attendance_submitted_by;
    prayer_changed :=
      new.prayer_submitted_at is distinct from old.prayer_submitted_at
      or new.prayer_source is distinct from old.prayer_source
      or new.prayer_submitted_by is distinct from old.prayer_submitted_by;
  end if;

  if new.attendance_submitted_at is not null
      and current_profile_id is not null
      and attendance_changed then
    new.attendance_submitted_by = current_profile_id;
    if new.attendance_source = 'backfill' then
      new.attendance_source = 'app';
    end if;
  end if;

  if new.prayer_submitted_at is not null
      and current_profile_id is not null
      and prayer_changed then
    new.prayer_submitted_by = current_profile_id;
    if new.prayer_source = 'backfill' then
      new.prayer_source = 'app';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists group_week_record_submissions_set_audit
  on public.group_week_record_submissions;

create trigger group_week_record_submissions_set_audit
  before insert or update on public.group_week_record_submissions
  for each row execute function public.set_group_week_record_submission_audit();

alter table public.group_week_record_submissions enable row level security;

drop policy if exists "group_week_record_submissions_select"
  on public.group_week_record_submissions;
drop policy if exists "group_week_record_submissions_insert"
  on public.group_week_record_submissions;
drop policy if exists "group_week_record_submissions_update"
  on public.group_week_record_submissions;

create policy "group_week_record_submissions_select"
  on public.group_week_record_submissions
  for select
  to authenticated
  using (
    public.check_is_master()
    or public.is_admin_approved(church_id)
    or exists (
      select 1
      from public.group_members gm
      where gm.group_id = group_week_record_submissions.group_id
        and gm.profile_id = auth.uid()
        and gm.role_in_group in ('leader', 'admin')
        and gm.is_active = true
    )
  );

create policy "group_week_record_submissions_insert"
  on public.group_week_record_submissions
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.groups g
      join public.departments d on d.id = g.department_id
      join public.weeks w on w.id = group_week_record_submissions.week_id
      where g.id = group_week_record_submissions.group_id
        and g.department_id = group_week_record_submissions.department_id
        and g.church_id = group_week_record_submissions.church_id
        and d.church_id = group_week_record_submissions.church_id
        and w.church_id = group_week_record_submissions.church_id
        and (
          public.check_is_master()
          or public.is_admin_approved(group_week_record_submissions.church_id)
          or exists (
            select 1
            from public.group_members gm
            where gm.group_id = group_week_record_submissions.group_id
              and gm.profile_id = auth.uid()
              and gm.role_in_group in ('leader', 'admin')
              and gm.is_active = true
          )
        )
    )
  );

create policy "group_week_record_submissions_update"
  on public.group_week_record_submissions
  for update
  to authenticated
  using (
    public.check_is_master()
    or public.is_admin_approved(church_id)
    or exists (
      select 1
      from public.group_members gm
      where gm.group_id = group_week_record_submissions.group_id
        and gm.profile_id = auth.uid()
        and gm.role_in_group in ('leader', 'admin')
        and gm.is_active = true
    )
  )
  with check (
    exists (
      select 1
      from public.groups g
      join public.departments d on d.id = g.department_id
      join public.weeks w on w.id = group_week_record_submissions.week_id
      where g.id = group_week_record_submissions.group_id
        and g.department_id = group_week_record_submissions.department_id
        and g.church_id = group_week_record_submissions.church_id
        and d.church_id = group_week_record_submissions.church_id
        and w.church_id = group_week_record_submissions.church_id
        and (
          public.check_is_master()
          or public.is_admin_approved(group_week_record_submissions.church_id)
          or exists (
            select 1
            from public.group_members gm
            where gm.group_id = group_week_record_submissions.group_id
              and gm.profile_id = auth.uid()
              and gm.role_in_group in ('leader', 'admin')
              and gm.is_active = true
          )
        )
    )
  );

grant select, insert, update on public.group_week_record_submissions to authenticated;

insert into public.group_week_record_submissions (
  church_id,
  department_id,
  week_id,
  group_id,
  attendance_submitted_at,
  attendance_source
)
select
  w.church_id,
  g.department_id,
  a.week_id,
  g.id,
  min(coalesce(a.updated_at, a.created_at, now())) as attendance_submitted_at,
  'backfill' as attendance_source
from public.attendance a
join public.groups g on g.id = coalesce(a.recorded_group_id, a.group_id)
join public.weeks w on w.id = a.week_id
left join public.no_meeting_days n
  on n.department_id = g.department_id
 and n.week_date = w.week_date
where a.status in ('present', 'late')
  and n.id is null
group by w.church_id, g.department_id, a.week_id, g.id
on conflict (week_id, group_id) do update
set attendance_submitted_at = coalesce(
      public.group_week_record_submissions.attendance_submitted_at,
      excluded.attendance_submitted_at
    ),
    attendance_source = coalesce(
      public.group_week_record_submissions.attendance_source,
      excluded.attendance_source
    );

insert into public.group_week_record_submissions (
  church_id,
  department_id,
  week_id,
  group_id,
  prayer_submitted_at,
  prayer_source
)
select
  w.church_id,
  g.department_id,
  p.week_id,
  g.id,
  min(coalesce(p.updated_at, p.created_at, now())) as prayer_submitted_at,
  'backfill' as prayer_source
from public.prayer_entries p
join public.groups g on g.id = coalesce(p.recorded_group_id, p.group_id)
join public.weeks w on w.id = p.week_id
left join public.no_meeting_days n
  on n.department_id = g.department_id
 and n.week_date = w.week_date
where p.status = 'published'
  and n.id is null
group by w.church_id, g.department_id, p.week_id, g.id
on conflict (week_id, group_id) do update
set prayer_submitted_at = coalesce(
      public.group_week_record_submissions.prayer_submitted_at,
      excluded.prayer_submitted_at
    ),
    prayer_source = coalesce(
      public.group_week_record_submissions.prayer_source,
      excluded.prayer_source
    );
