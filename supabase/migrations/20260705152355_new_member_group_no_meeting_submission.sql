begin;

alter table public.group_week_record_submissions
  add column if not exists attendance_submission_kind text not null default 'records',
  add column if not exists prayer_submission_kind text not null default 'records',
  add column if not exists submission_note text null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'group_week_record_submissions_attendance_kind_check'
      and conrelid = 'public.group_week_record_submissions'::regclass
  ) then
    alter table public.group_week_record_submissions
      add constraint group_week_record_submissions_attendance_kind_check
      check (attendance_submission_kind in ('records', 'no_meeting'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'group_week_record_submissions_prayer_kind_check'
      and conrelid = 'public.group_week_record_submissions'::regclass
  ) then
    alter table public.group_week_record_submissions
      add constraint group_week_record_submissions_prayer_kind_check
      check (prayer_submission_kind in ('records', 'no_meeting'));
  end if;
end $$;

alter table public.attendance
  drop constraint if exists attendance_week_id_directory_member_id_key;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'attendance_week_id_directory_member_id_group_id_key'
      and conrelid = 'public.attendance'::regclass
  ) then
    alter table public.attendance
      add constraint attendance_week_id_directory_member_id_group_id_key
      unique (week_id, directory_member_id, group_id);
  end if;
end $$;

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
    new.attendance_submission_kind = 'records';
  elsif new.attendance_source is null then
    new.attendance_source = 'app';
  end if;

  if new.attendance_submitted_at is not null and new.attendance_submission_kind is null then
    new.attendance_submission_kind = 'records';
  end if;

  if new.prayer_submitted_at is null then
    new.prayer_submitted_by = null;
    new.prayer_source = null;
    new.prayer_submission_kind = 'records';
  elsif new.prayer_source is null then
    new.prayer_source = 'app';
  end if;

  if new.prayer_submitted_at is not null and new.prayer_submission_kind is null then
    new.prayer_submission_kind = 'records';
  end if;

  if tg_op = 'INSERT' then
    attendance_changed := true;
    prayer_changed := true;
  else
    attendance_changed :=
      new.attendance_submitted_at is distinct from old.attendance_submitted_at
      or new.attendance_source is distinct from old.attendance_source
      or new.attendance_submission_kind is distinct from old.attendance_submission_kind
      or new.attendance_submitted_by is distinct from old.attendance_submitted_by;
    prayer_changed :=
      new.prayer_submitted_at is distinct from old.prayer_submitted_at
      or new.prayer_source is distinct from old.prayer_source
      or new.prayer_submission_kind is distinct from old.prayer_submission_kind
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

create or replace function public.can_manage_group_week_record_submission(
  p_group_id uuid,
  p_week_id uuid,
  p_church_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with target_week as (
    select w.week_date
    from public.weeks w
    where w.id = p_week_id
      and w.church_id = p_church_id
    limit 1
  ),
  current_profile as (
    select p.id, p.person_id
    from public.profiles p
    where p.id = auth.uid()
    limit 1
  )
  select coalesce(
    current_setting('request.jwt.claim.role', true) = 'service_role'
    or coalesce(public.check_is_master(), false)
    or coalesce(public.is_admin_approved(p_church_id), false)
    or exists (
      select 1
      from public.group_members gm
      join current_profile cp
        on cp.id = gm.profile_id
      where gm.group_id = p_group_id
        and gm.role_in_group in ('leader', 'admin')
        and gm.is_active = true
    )
    or exists (
      select 1
      from public.memberships m
      join current_profile cp
        on cp.person_id = m.person_id
      join target_week tw
        on true
      where m.group_id = p_group_id
        and m.role in ('leader', 'admin')
        and m.status in ('active', 'ended')
        and (m.starts_at is null or m.starts_at::date <= tw.week_date)
        and (m.ends_at is null or m.ends_at::date >= tw.week_date)
    ),
    false
  );
$$;

revoke all on function public.can_manage_group_week_record_submission(uuid, uuid, uuid) from public;
grant execute on function public.can_manage_group_week_record_submission(uuid, uuid, uuid)
  to authenticated, service_role;

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
    public.can_manage_group_week_record_submission(group_id, week_id, church_id)
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
        and public.can_manage_group_week_record_submission(
          group_week_record_submissions.group_id,
          group_week_record_submissions.week_id,
          group_week_record_submissions.church_id
        )
    )
  );

create policy "group_week_record_submissions_update"
  on public.group_week_record_submissions
  for update
  to authenticated
  using (
    public.can_manage_group_week_record_submission(group_id, week_id, church_id)
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
        and public.can_manage_group_week_record_submission(
          group_week_record_submissions.group_id,
          group_week_record_submissions.week_id,
          group_week_record_submissions.church_id
        )
    )
  );

create or replace function public.mark_new_member_group_no_meeting(
  p_church_id uuid,
  p_department_id uuid,
  p_week_id uuid,
  p_group_id uuid,
  p_reason text default '새가족 모임 없음'
)
returns table (
  group_id uuid,
  week_id uuid,
  absent_member_count integer,
  attendance_submission_kind text,
  prayer_submission_kind text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.groups%rowtype;
  v_week public.weeks%rowtype;
  v_plan_group_id uuid;
  v_absent_count integer := 0;
begin
  select *
  into v_group
  from public.groups
  where id = p_group_id
    and church_id = p_church_id
    and department_id = p_department_id;

  if not found then
    raise exception 'target group was not found.';
  end if;

  if coalesce(v_group.is_new_member_group, false) is not true then
    raise exception 'only new member groups can submit no-meeting records.';
  end if;

  select *
  into v_week
  from public.weeks
  where id = p_week_id
    and church_id = p_church_id;

  if not found then
    raise exception 'target week was not found.';
  end if;

  if not public.can_manage_group_week_record_submission(
    p_group_id,
    p_week_id,
    p_church_id
  ) then
    raise exception 'not allowed to submit new member group no-meeting records.';
  end if;

  if exists (
    select 1
    from public.attendance a
    where a.week_id = p_week_id
      and coalesce(a.recorded_group_id, a.group_id) = p_group_id
      and a.status in ('present', 'late')
  ) then
    raise exception 'cannot mark no meeting after present attendance was recorded.';
  end if;

  if exists (
    select 1
    from public.prayer_entries pe
    where pe.week_id = p_week_id
      and coalesce(pe.recorded_group_id, pe.group_id) = p_group_id
      and pe.status = 'published'
  ) then
    raise exception 'cannot mark no meeting after published prayers were recorded.';
  end if;

  select rpg.id
  into v_plan_group_id
  from public.regrouping_seasons rs
  join public.regrouping_plan_groups rpg
    on rpg.season_id = rs.id
   and rpg.source_group_id = p_group_id
  where rs.department_id = p_department_id
    and rs.status = 'applied'
    and rs.effective_week_date <= v_week.week_date
    and (rs.end_week_date is null or rs.end_week_date >= v_week.week_date)
    and coalesce(rpg.plan_status, 'active') <> 'ended'
    and coalesce(rpg.starts_week_date, rs.effective_week_date) <= v_week.week_date
    and (rpg.ends_week_date is null or rpg.ends_week_date >= v_week.week_date)
  order by rs.effective_week_date desc, rs.updated_at desc
  limit 1;

  if v_plan_group_id is not null then
    with target_members as (
      select distinct on (rpa.person_id, rpa.source_member_directory_id)
        rpa.source_member_directory_id as directory_member_id,
        rpa.person_id,
        rpa.source_membership_id as membership_id
      from public.regrouping_plan_assignments rpa
      where rpa.plan_group_id = v_plan_group_id
        and rpa.role_in_group = 'member'
        and rpa.source_member_directory_id is not null
        and rpa.starts_week_date <= v_week.week_date
        and (rpa.ends_week_date is null or rpa.ends_week_date >= v_week.week_date)
      order by rpa.person_id, rpa.source_member_directory_id, rpa.sort_order, rpa.updated_at desc
    ),
    upserted as (
      insert into public.attendance (
        week_id,
        group_id,
        directory_member_id,
        person_id,
        membership_id,
        recorded_group_id,
        recorded_department_id,
        status,
        updated_at
      )
      select
        p_week_id,
        p_group_id,
        target_members.directory_member_id,
        target_members.person_id,
        target_members.membership_id,
        p_group_id,
        p_department_id,
        'absent',
        now()
      from target_members
      on conflict on constraint attendance_week_id_directory_member_id_group_id_key
      do update
      set status = 'absent',
          person_id = coalesce(excluded.person_id, public.attendance.person_id),
          membership_id = coalesce(excluded.membership_id, public.attendance.membership_id),
          recorded_group_id = excluded.recorded_group_id,
          recorded_department_id = excluded.recorded_department_id,
          updated_at = now()
      returning 1
    )
    select count(*)::integer
    into v_absent_count
    from upserted;
  else
    with target_members as (
      select distinct on (m.person_id, m.legacy_member_directory_id)
        m.legacy_member_directory_id as directory_member_id,
        m.person_id,
        m.id as membership_id
      from public.memberships m
      where m.group_id = p_group_id
        and m.department_id = p_department_id
        and m.role = 'member'
        and m.legacy_member_directory_id is not null
        and m.status in ('active', 'ended')
        and (m.starts_at is null or m.starts_at::date <= v_week.week_date)
        and (m.ends_at is null or m.ends_at::date >= v_week.week_date)
      order by m.person_id, m.legacy_member_directory_id, m.updated_at desc, m.starts_at desc nulls last
    ),
    upserted as (
      insert into public.attendance (
        week_id,
        group_id,
        directory_member_id,
        person_id,
        membership_id,
        recorded_group_id,
        recorded_department_id,
        status,
        updated_at
      )
      select
        p_week_id,
        p_group_id,
        target_members.directory_member_id,
        target_members.person_id,
        target_members.membership_id,
        p_group_id,
        p_department_id,
        'absent',
        now()
      from target_members
      on conflict on constraint attendance_week_id_directory_member_id_group_id_key
      do update
      set status = 'absent',
          person_id = coalesce(excluded.person_id, public.attendance.person_id),
          membership_id = coalesce(excluded.membership_id, public.attendance.membership_id),
          recorded_group_id = excluded.recorded_group_id,
          recorded_department_id = excluded.recorded_department_id,
          updated_at = now()
      returning 1
    )
    select count(*)::integer
    into v_absent_count
    from upserted;
  end if;

  insert into public.group_week_record_submissions (
    church_id,
    department_id,
    week_id,
    group_id,
    attendance_submitted_at,
    attendance_source,
    attendance_submission_kind,
    prayer_submitted_at,
    prayer_source,
    prayer_submission_kind,
    submission_note
  )
  values (
    p_church_id,
    p_department_id,
    p_week_id,
    p_group_id,
    now(),
    'app',
    'no_meeting',
    now(),
    'app',
    'no_meeting',
    nullif(trim(coalesce(p_reason, '')), '')
  )
  on conflict on constraint group_week_record_submissions_week_group_unique
  do update
  set attendance_submitted_at = now(),
      attendance_source = 'app',
      attendance_submission_kind = 'no_meeting',
      prayer_submitted_at = now(),
      prayer_source = 'app',
      prayer_submission_kind = 'no_meeting',
      submission_note = excluded.submission_note,
      updated_at = now();

  return query
  select
    p_group_id,
    p_week_id,
    v_absent_count,
    'no_meeting'::text,
    'no_meeting'::text;
end;
$$;

revoke all on function public.mark_new_member_group_no_meeting(uuid, uuid, uuid, uuid, text) from public;
grant execute on function public.mark_new_member_group_no_meeting(uuid, uuid, uuid, uuid, text)
  to authenticated, service_role;

create or replace function public.cancel_new_member_group_no_meeting(
  p_church_id uuid,
  p_department_id uuid,
  p_week_id uuid,
  p_group_id uuid
)
returns table (
  group_id uuid,
  week_id uuid,
  removed_attendance_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.groups%rowtype;
  v_removed_count integer := 0;
begin
  select *
  into v_group
  from public.groups
  where id = p_group_id
    and church_id = p_church_id
    and department_id = p_department_id;

  if not found then
    raise exception 'target group was not found.';
  end if;

  if coalesce(v_group.is_new_member_group, false) is not true then
    raise exception 'only new member groups can cancel no-meeting records.';
  end if;

  if not exists (
    select 1
    from public.weeks w
    where w.id = p_week_id
      and w.church_id = p_church_id
  ) then
    raise exception 'target week was not found.';
  end if;

  if not public.can_manage_group_week_record_submission(
    p_group_id,
    p_week_id,
    p_church_id
  ) then
    raise exception 'not allowed to cancel new member group no-meeting records.';
  end if;

  if not exists (
    select 1
    from public.group_week_record_submissions gwrs
    where gwrs.week_id = p_week_id
      and gwrs.group_id = p_group_id
      and gwrs.church_id = p_church_id
      and gwrs.department_id = p_department_id
      and gwrs.attendance_submission_kind = 'no_meeting'
      and gwrs.prayer_submission_kind = 'no_meeting'
  ) then
    return query
    select p_group_id, p_week_id, 0;
    return;
  end if;

  delete from public.attendance a
  where a.week_id = p_week_id
    and coalesce(a.recorded_group_id, a.group_id) = p_group_id
    and a.status = 'absent';

  get diagnostics v_removed_count = row_count;

  delete from public.group_week_record_submissions gwrs
  where gwrs.week_id = p_week_id
    and gwrs.group_id = p_group_id
    and gwrs.church_id = p_church_id
    and gwrs.department_id = p_department_id
    and gwrs.attendance_submission_kind = 'no_meeting'
    and gwrs.prayer_submission_kind = 'no_meeting';

  return query
  select p_group_id, p_week_id, v_removed_count;
end;
$$;

revoke all on function public.cancel_new_member_group_no_meeting(uuid, uuid, uuid, uuid) from public;
grant execute on function public.cancel_new_member_group_no_meeting(uuid, uuid, uuid, uuid)
  to authenticated, service_role;

commit;
