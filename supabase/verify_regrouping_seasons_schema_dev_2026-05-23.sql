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
