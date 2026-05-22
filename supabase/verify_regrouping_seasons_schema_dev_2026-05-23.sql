-- Dev/staging verification for Phase 3 regrouping season schema.
-- This file is read-only except for rollback-protected smoke rows.

select
  'regrouping_season_tables_exist' as check_name,
  count(*) filter (
    where table_name in (
      'regrouping_seasons',
      'regrouping_plan_groups',
      'regrouping_plan_assignments'
    )
  ) as actual,
  3 as expected
from information_schema.tables
where table_schema = 'public';

select
  'regrouping_season_indexes_exist' as check_name,
  count(*) filter (
    where indexname in (
      'regrouping_seasons_unique_active_effective_week',
      'regrouping_seasons_department_status_idx',
      'regrouping_seasons_department_effective_week_idx',
      'regrouping_plan_groups_season_sort_idx',
      'regrouping_plan_groups_source_group_idx',
      'regrouping_plan_assignments_unique_person_group',
      'regrouping_plan_assignments_unique_unassigned_person',
      'regrouping_plan_assignments_person_idx',
      'regrouping_plan_assignments_group_sort_idx'
    )
  ) as actual,
  9 as expected
from pg_indexes
where schemaname = 'public';

select
  'regrouping_season_rls_enabled' as check_name,
  count(*) filter (
    where relname in (
      'regrouping_seasons',
      'regrouping_plan_groups',
      'regrouping_plan_assignments'
    )
    and relrowsecurity
  ) as actual,
  3 as expected
from pg_class
where relnamespace = 'public'::regnamespace;

select
  'regrouping_season_policies_exist' as check_name,
  count(*) filter (
    where policyname in (
      'regrouping_seasons_select_same_church',
      'regrouping_seasons_manage_admin',
      'regrouping_plan_groups_select_same_church',
      'regrouping_plan_groups_manage_admin',
      'regrouping_plan_assignments_select_same_church',
      'regrouping_plan_assignments_manage_admin'
    )
  ) as actual,
  6 as expected
from pg_policies
where schemaname = 'public';

select
  'regrouping_season_draft_functions_exist' as check_name,
  count(*) filter (
    where proname in (
      'create_regrouping_season',
      'save_regrouping_season_draft'
    )
  ) as actual,
  2 as expected
from pg_proc
where pronamespace = 'public'::regnamespace;

begin;

with target_department as (
  select
    d.id as department_id,
    d.church_id
  from public.departments d
  where d.is_active is distinct from false
    and exists (
      select 1
      from public.profiles p
      where p.church_id = d.church_id
        and p.role = 'admin'
        and p.admin_status = 'approved'
    )
    and exists (
      select 1
      from public.memberships m
      where m.department_id = d.id
        and m.status = 'active'
        and m.person_id is not null
    )
  order by d.created_at desc nulls last
  limit 1
),
target_admin as (
  select p.id as profile_id
  from public.profiles p
  join target_department td
    on td.church_id = p.church_id
  where p.role = 'admin'
    and p.admin_status = 'approved'
  order by p.created_at desc nulls last
  limit 1
),
auth_context as (
  select set_config('request.jwt.claim.sub', profile_id::text, true)
  from target_admin
),
target_person as (
  select
    m.person_id,
    m.id as source_membership_id,
    m.legacy_member_directory_id as source_member_directory_id
  from public.memberships m
  join target_department td
    on td.department_id = m.department_id
  where m.status = 'active'
    and m.person_id is not null
  order by m.updated_at desc nulls last, m.created_at desc nulls last
  limit 1
),
live_before as (
  select
    (select count(*) from public.groups) as groups_count,
    (select count(*) from public.member_directory) as member_directory_count,
    (select count(*) from public.group_members) as group_members_count,
    (select count(*) from public.memberships) as memberships_count
),
created as (
  select public.create_regrouping_season(
    td.church_id,
    td.department_id,
    'verify regrouping season draft',
    date '2026-05-24'
  ) as season_id
  from target_department td
  cross join auth_context
),
saved as (
  select *
  from public.save_regrouping_season_draft(
    (select season_id from created),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'verify-client-group',
        'name', 'verify group',
        'sort_order', 1
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'group_id', 'verify-client-group',
        'person_id', (select person_id from target_person),
        'source_membership_id', (select source_membership_id from target_person),
        'source_member_directory_id', (select source_member_directory_id from target_person),
        'role_in_group', 'member',
        'sort_order', 1
      )
    )
  )
),
live_after as (
  select
    (select count(*) from public.groups) as groups_count,
    (select count(*) from public.member_directory) as member_directory_count,
    (select count(*) from public.group_members) as group_members_count,
    (select count(*) from public.memberships) as memberships_count
)
select
  'regrouping_draft_save_no_live_write' as check_name,
  (select case when season_id is not null then 1 else 0 end from created) as created_season_returned,
  (select plan_group_count from saved) as plan_group_count,
  (select assignment_count from saved) as assignment_count,
  (
    select case when
      live_before.groups_count = live_after.groups_count
      and live_before.member_directory_count = live_after.member_directory_count
      and live_before.group_members_count = live_after.group_members_count
      and live_before.memberships_count = live_after.memberships_count
    then 1 else 0 end
    from live_before, live_after
  ) as live_counts_unchanged;

rollback;
