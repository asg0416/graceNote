-- Phase 3 regrouping seasons:
-- Store future regrouping drafts separately from live groups/memberships.
-- Draft rows must not affect Flutter prayer/attendance or admin attendance
-- screens until an explicit apply RPC transitions the season to live state.

set check_function_bodies = off;

create table if not exists public.regrouping_seasons (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  title text not null,
  status text not null default 'draft',
  effective_week_date date not null,
  created_by uuid references public.profiles(id) on delete set null,
  applied_by uuid references public.profiles(id) on delete set null,
  applied_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint regrouping_seasons_title_not_blank
    check (btrim(title) <> ''),
  constraint regrouping_seasons_status_check
    check (status in ('draft', 'ready', 'applied', 'archived', 'cancelled')),
  constraint regrouping_seasons_effective_week_sunday_check
    check (extract(dow from effective_week_date) = 0),
  constraint regrouping_seasons_applied_state_check
    check (
      (status = 'applied' and applied_at is not null)
      or (status <> 'applied' and applied_at is null)
    )
);

create unique index if not exists regrouping_seasons_unique_active_effective_week
on public.regrouping_seasons (church_id, department_id, effective_week_date)
where status in ('draft', 'ready', 'applied');

create index if not exists regrouping_seasons_department_status_idx
on public.regrouping_seasons (church_id, department_id, status);

create index if not exists regrouping_seasons_department_effective_week_idx
on public.regrouping_seasons (church_id, department_id, effective_week_date desc);

create table if not exists public.regrouping_plan_groups (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.regrouping_seasons(id) on delete cascade,
  source_group_id uuid references public.groups(id) on delete set null,
  name text not null,
  color_hex text,
  sort_order integer not null default 0,
  leader_person_id uuid references public.people(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint regrouping_plan_groups_name_not_blank check (btrim(name) <> '')
);

create index if not exists regrouping_plan_groups_season_sort_idx
on public.regrouping_plan_groups (season_id, sort_order, name);

create index if not exists regrouping_plan_groups_source_group_idx
on public.regrouping_plan_groups (season_id, source_group_id);

create table if not exists public.regrouping_plan_assignments (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.regrouping_seasons(id) on delete cascade,
  plan_group_id uuid references public.regrouping_plan_groups(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete cascade,
  role_in_group text not null default 'member',
  sort_order integer not null default 0,
  source_membership_id uuid references public.memberships(id) on delete set null,
  source_member_directory_id uuid references public.member_directory(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint regrouping_plan_assignments_role_check
    check (role_in_group in ('leader', 'member', 'admin', 'sub_leader'))
);

create unique index if not exists regrouping_plan_assignments_unique_person_group
on public.regrouping_plan_assignments (season_id, plan_group_id, person_id)
where plan_group_id is not null;

create unique index if not exists regrouping_plan_assignments_unique_unassigned_person
on public.regrouping_plan_assignments (season_id, person_id)
where plan_group_id is null;

create index if not exists regrouping_plan_assignments_person_idx
on public.regrouping_plan_assignments (season_id, person_id);

create index if not exists regrouping_plan_assignments_group_sort_idx
on public.regrouping_plan_assignments (season_id, plan_group_id, sort_order);

alter table public.regrouping_seasons enable row level security;
alter table public.regrouping_plan_groups enable row level security;
alter table public.regrouping_plan_assignments enable row level security;

drop policy if exists regrouping_seasons_select_same_church on public.regrouping_seasons;
create policy regrouping_seasons_select_same_church
on public.regrouping_seasons
for select
to authenticated
using (
  public.check_is_master()
  or public.is_admin_approved(church_id)
  or church_id = public.get_my_church_id()
);

drop policy if exists regrouping_seasons_manage_admin on public.regrouping_seasons;
create policy regrouping_seasons_manage_admin
on public.regrouping_seasons
for all
to authenticated
using (
  public.check_is_master()
  or public.is_admin_approved(church_id)
)
with check (
  public.check_is_master()
  or public.is_admin_approved(church_id)
);

drop policy if exists regrouping_plan_groups_select_same_church on public.regrouping_plan_groups;
create policy regrouping_plan_groups_select_same_church
on public.regrouping_plan_groups
for select
to authenticated
using (
  exists (
    select 1
    from public.regrouping_seasons s
    where s.id = regrouping_plan_groups.season_id
      and (
        public.check_is_master()
        or public.is_admin_approved(s.church_id)
        or s.church_id = public.get_my_church_id()
      )
  )
);

drop policy if exists regrouping_plan_groups_manage_admin on public.regrouping_plan_groups;
create policy regrouping_plan_groups_manage_admin
on public.regrouping_plan_groups
for all
to authenticated
using (
  exists (
    select 1
    from public.regrouping_seasons s
    where s.id = regrouping_plan_groups.season_id
      and (
        public.check_is_master()
        or public.is_admin_approved(s.church_id)
      )
  )
)
with check (
  exists (
    select 1
    from public.regrouping_seasons s
    where s.id = regrouping_plan_groups.season_id
      and (
        public.check_is_master()
        or public.is_admin_approved(s.church_id)
      )
  )
);

drop policy if exists regrouping_plan_assignments_select_same_church on public.regrouping_plan_assignments;
create policy regrouping_plan_assignments_select_same_church
on public.regrouping_plan_assignments
for select
to authenticated
using (
  exists (
    select 1
    from public.regrouping_seasons s
    where s.id = regrouping_plan_assignments.season_id
      and (
        public.check_is_master()
        or public.is_admin_approved(s.church_id)
        or s.church_id = public.get_my_church_id()
      )
  )
);

drop policy if exists regrouping_plan_assignments_manage_admin on public.regrouping_plan_assignments;
create policy regrouping_plan_assignments_manage_admin
on public.regrouping_plan_assignments
for all
to authenticated
using (
  exists (
    select 1
    from public.regrouping_seasons s
    where s.id = regrouping_plan_assignments.season_id
      and (
        public.check_is_master()
        or public.is_admin_approved(s.church_id)
      )
  )
)
with check (
  exists (
    select 1
    from public.regrouping_seasons s
    where s.id = regrouping_plan_assignments.season_id
      and (
        public.check_is_master()
        or public.is_admin_approved(s.church_id)
      )
  )
);

grant select, insert, update, delete on public.regrouping_seasons to authenticated, service_role;
grant select, insert, update, delete on public.regrouping_plan_groups to authenticated, service_role;
grant select, insert, update, delete on public.regrouping_plan_assignments to authenticated, service_role;
