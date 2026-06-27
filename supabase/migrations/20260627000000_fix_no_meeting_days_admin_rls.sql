drop policy if exists "no_meeting_days_select" on public.no_meeting_days;
drop policy if exists "no_meeting_days_write" on public.no_meeting_days;

create policy "no_meeting_days_select"
  on public.no_meeting_days
  for select
  to authenticated
  using (
    public.check_is_master()
    or exists (
      select 1
      from public.departments d
      where d.id = no_meeting_days.department_id
        and public.is_admin_approved(d.church_id)
    )
    or department_id in (
      select p.department_id
      from public.profiles p
      where p.id = auth.uid()
        and p.department_id is not null
    )
  );

create policy "no_meeting_days_write"
  on public.no_meeting_days
  for all
  to authenticated
  using (
    public.check_is_master()
    or exists (
      select 1
      from public.departments d
      where d.id = no_meeting_days.department_id
        and public.is_admin_approved(d.church_id)
    )
  )
  with check (
    public.check_is_master()
    or exists (
      select 1
      from public.departments d
      where d.id = no_meeting_days.department_id
        and public.is_admin_approved(d.church_id)
    )
  );
