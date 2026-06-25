-- Query-compatible summary gate for Phase 3 regrouping seasons.
-- Returns `check_name, issue_count` rows only so it can be consumed by
-- scripts/preprod-verify-gates*.mjs.

select 'regrouping_season_tables_missing' as check_name,
  case when count(*) filter (
    where table_name in (
      'regrouping_seasons',
      'regrouping_plan_groups',
      'regrouping_plan_assignments'
    )
  ) = 3 then 0 else 1 end::bigint as issue_count
from information_schema.tables
where table_schema = 'public';

select 'regrouping_season_indexes_missing' as check_name,
  case when count(*) filter (
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
  ) = 9 then 0 else 1 end::bigint as issue_count
from pg_indexes
where schemaname = 'public';

select 'regrouping_season_rls_missing' as check_name,
  case when count(*) filter (
    where relname in (
      'regrouping_seasons',
      'regrouping_plan_groups',
      'regrouping_plan_assignments'
    )
    and relrowsecurity
  ) = 3 then 0 else 1 end::bigint as issue_count
from pg_class
where relnamespace = 'public'::regnamespace;

select 'regrouping_season_policies_missing' as check_name,
  case when count(*) filter (
    where policyname in (
      'regrouping_seasons_select_same_church',
      'regrouping_seasons_manage_admin',
      'regrouping_plan_groups_select_same_church',
      'regrouping_plan_groups_manage_admin',
      'regrouping_plan_assignments_select_same_church',
      'regrouping_plan_assignments_manage_admin'
    )
  ) = 6 then 0 else 1 end::bigint as issue_count
from pg_policies
where schemaname = 'public';

select 'regrouping_season_functions_missing' as check_name,
  case when count(distinct proname) filter (
    where proname in (
      'create_regrouping_season',
      'save_regrouping_season_draft',
      'update_regrouping_season',
      'apply_regrouping_season'
    )
  ) = 4 then 0 else 1 end::bigint as issue_count
from pg_proc
where pronamespace = 'public'::regnamespace;

begin;

create temporary table pg_temp.verify_regrouping_summary_target on commit drop as
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
)
select
  td.church_id,
  td.department_id,
  tp.person_id,
  tp.source_membership_id,
  tp.source_member_directory_id,
  (current_date - extract(dow from current_date)::integer)::date as current_week_date,
  (current_date - extract(dow from current_date)::integer)::date as current_end_week_date,
  ((current_date - extract(dow from current_date)::integer)::date + interval '28 days')::date as future_week_date,
  ((current_date - extract(dow from current_date)::integer)::date + interval '28 days')::date as future_end_week_date
from target_department td
cross join auth_context
cross join target_person tp;

create temporary table pg_temp.verify_regrouping_summary_counts (
  label text primary key,
  groups_count bigint,
  member_directory_count bigint,
  group_members_count bigint,
  memberships_count bigint
) on commit drop;

insert into pg_temp.verify_regrouping_summary_counts
select
  'before_future_draft',
  (select count(*) from public.groups),
  (select count(*) from public.member_directory),
  (select count(*) from public.group_members),
  (select count(*) from public.memberships);

create temporary table pg_temp.verify_regrouping_summary_seasons (
  label text primary key,
  season_id uuid,
  plan_group_count integer,
  assignment_count integer,
  apply_rejected integer default 0,
  season_applied integer default 0,
  active_membership_from_effective_week integer default 0
) on commit drop;

insert into pg_temp.verify_regrouping_summary_seasons (label, season_id)
select
  'future',
  public.create_regrouping_season(
    church_id,
    department_id,
    'verify summary future regrouping draft',
    future_week_date,
    future_end_week_date
  )
from pg_temp.verify_regrouping_summary_target;

with saved as (
  select *
  from public.save_regrouping_season_draft(
    (select season_id from pg_temp.verify_regrouping_summary_seasons where label = 'future'),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'verify-summary-future-group',
        'name', 'verify summary future group',
        'sort_order', 1
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'group_id', 'verify-summary-future-group',
        'person_id', (select person_id from pg_temp.verify_regrouping_summary_target),
        'source_membership_id', (select source_membership_id from pg_temp.verify_regrouping_summary_target),
        'source_member_directory_id', (select source_member_directory_id from pg_temp.verify_regrouping_summary_target),
        'role_in_group', 'member',
        'sort_order', 1
      )
    )
  )
)
update pg_temp.verify_regrouping_summary_seasons season
set
  plan_group_count = saved.plan_group_count,
  assignment_count = saved.assignment_count
from saved
where season.label = 'future';

do $$
begin
  perform public.update_regrouping_season(
    (select season_id from pg_temp.verify_regrouping_summary_seasons where label = 'future'),
    'verify summary future regrouping draft updated',
    (select future_week_date from pg_temp.verify_regrouping_summary_target),
    (select future_end_week_date from pg_temp.verify_regrouping_summary_target)
  );
end;
$$;

insert into pg_temp.verify_regrouping_summary_counts
select
  'after_future_draft',
  (select count(*) from public.groups),
  (select count(*) from public.member_directory),
  (select count(*) from public.group_members),
  (select count(*) from public.memberships);

do $$
begin
  perform public.apply_regrouping_season(
    (select season_id from pg_temp.verify_regrouping_summary_seasons where label = 'future')
  );

  raise exception 'future apply unexpectedly succeeded.';
exception
  when others then
    if position('future regrouping seasons cannot be applied before the effective week' in sqlerrm) = 0 then
      raise;
    end if;

    update pg_temp.verify_regrouping_summary_seasons
    set apply_rejected = 1
    where label = 'future';
end;
$$;

insert into pg_temp.verify_regrouping_summary_seasons (label, season_id)
select
  'current',
  public.create_regrouping_season(
    church_id,
    department_id,
    'verify summary current regrouping apply',
    current_week_date,
    current_end_week_date
  )
from pg_temp.verify_regrouping_summary_target;

with saved as (
  select *
  from public.save_regrouping_season_draft(
    (select season_id from pg_temp.verify_regrouping_summary_seasons where label = 'current'),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'verify-summary-current-group',
        'name', 'verify summary current group',
        'sort_order', 1
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'group_id', 'verify-summary-current-group',
        'person_id', (select person_id from pg_temp.verify_regrouping_summary_target),
        'source_membership_id', (select source_membership_id from pg_temp.verify_regrouping_summary_target),
        'source_member_directory_id', (select source_member_directory_id from pg_temp.verify_regrouping_summary_target),
        'role_in_group', 'member',
        'sort_order', 1
      )
    )
  )
)
update pg_temp.verify_regrouping_summary_seasons season
set
  plan_group_count = saved.plan_group_count,
  assignment_count = saved.assignment_count
from saved
where season.label = 'current';

do $$
begin
  perform public.update_regrouping_season(
    (select season_id from pg_temp.verify_regrouping_summary_seasons where label = 'current'),
    'verify summary current regrouping apply updated',
    (select current_week_date from pg_temp.verify_regrouping_summary_target),
    (select current_end_week_date from pg_temp.verify_regrouping_summary_target)
  );

  perform public.apply_regrouping_season(
    (select season_id from pg_temp.verify_regrouping_summary_seasons where label = 'current')
  );
end;
$$;

update pg_temp.verify_regrouping_summary_seasons season
set
  season_applied = (
    select case when rs.status = 'applied' and rs.applied_at is not null then 1 else 0 end
    from public.regrouping_seasons rs
    where rs.id = season.season_id
  ),
  active_membership_from_effective_week = (
    select count(*)::integer
    from public.memberships m
    join public.groups g
      on g.id = m.group_id
    where m.person_id = (select person_id from pg_temp.verify_regrouping_summary_target)
      and m.department_id = (select department_id from pg_temp.verify_regrouping_summary_target)
      and m.status = 'active'
      and m.starts_at::date <= (select current_week_date from pg_temp.verify_regrouping_summary_target)
      and g.name = 'verify summary current group'
  )
where season.label = 'current';

select
  'regrouping_future_draft_live_write_or_apply_failure' as check_name,
  case when
    (select plan_group_count from pg_temp.verify_regrouping_summary_seasons where label = 'future') = 1
    and (select assignment_count from pg_temp.verify_regrouping_summary_seasons where label = 'future') = 1
    and (select apply_rejected from pg_temp.verify_regrouping_summary_seasons where label = 'future') = 1
    and (
      select before_counts.groups_count = after_counts.groups_count
        and before_counts.member_directory_count = after_counts.member_directory_count
        and before_counts.group_members_count = after_counts.group_members_count
        and before_counts.memberships_count = after_counts.memberships_count
      from pg_temp.verify_regrouping_summary_counts before_counts
      join pg_temp.verify_regrouping_summary_counts after_counts
        on after_counts.label = 'after_future_draft'
      where before_counts.label = 'before_future_draft'
    )
  then 0 else 1 end::bigint as issue_count;

select
  'regrouping_current_apply_failure' as check_name,
  case when
    (select plan_group_count from pg_temp.verify_regrouping_summary_seasons where label = 'current') = 1
    and (select assignment_count from pg_temp.verify_regrouping_summary_seasons where label = 'current') = 1
    and (select season_applied from pg_temp.verify_regrouping_summary_seasons where label = 'current') = 1
    and (select active_membership_from_effective_week from pg_temp.verify_regrouping_summary_seasons where label = 'current') = 1
  then 0 else 1 end::bigint as issue_count;

rollback;
