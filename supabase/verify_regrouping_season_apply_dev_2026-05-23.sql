-- Dev/staging rollback verifier for applying a regrouping season.

begin;

create temporary table pg_temp.verify_regrouping_apply_target on commit drop as
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
  (current_date - extract(dow from current_date)::integer)::date as effective_week_date,
  'verify apply group'::text as plan_group_name
from target_department td
cross join auth_context
cross join target_person tp;

create temporary table pg_temp.verify_regrouping_apply_season (
  season_id uuid,
  created_group_count integer,
  ended_group_count integer,
  created_membership_count integer,
  ended_membership_count integer,
  affected_person_count integer
) on commit drop;

insert into pg_temp.verify_regrouping_apply_season (season_id)
select public.create_regrouping_season(
  church_id,
  department_id,
  'verify apply regrouping season',
  effective_week_date
)
from pg_temp.verify_regrouping_apply_target;

select *
from public.save_regrouping_season_draft(
  (select season_id from pg_temp.verify_regrouping_apply_season),
  jsonb_build_array(
    jsonb_build_object(
      'id', 'verify-apply-group',
      'name', (select plan_group_name from pg_temp.verify_regrouping_apply_target),
      'sort_order', 1
    )
  ),
  jsonb_build_array(
    jsonb_build_object(
      'group_id', 'verify-apply-group',
      'person_id', (select person_id from pg_temp.verify_regrouping_apply_target),
      'source_membership_id', (select source_membership_id from pg_temp.verify_regrouping_apply_target),
      'source_member_directory_id', (select source_member_directory_id from pg_temp.verify_regrouping_apply_target),
      'role_in_group', 'member',
      'sort_order', 1
    )
  )
);

with result as (
  select *
  from public.apply_regrouping_season(
    (select season_id from pg_temp.verify_regrouping_apply_season)
  )
)
update pg_temp.verify_regrouping_apply_season s
set
  created_group_count = result.created_group_count,
  ended_group_count = result.ended_group_count,
  created_membership_count = result.created_membership_count,
  ended_membership_count = result.ended_membership_count,
  affected_person_count = result.affected_person_count
from result;

select
  'regrouping_season_apply' as check_name,
  (
    select case when rs.status = 'applied' and rs.applied_at is not null then 1 else 0 end
    from public.regrouping_seasons rs
    where rs.id = (select season_id from pg_temp.verify_regrouping_apply_season)
  ) as season_applied,
  (
    select count(*)::integer
    from public.memberships m
    join public.groups g
      on g.id = m.group_id
    where m.person_id = (select person_id from pg_temp.verify_regrouping_apply_target)
      and m.department_id = (select department_id from pg_temp.verify_regrouping_apply_target)
      and m.status = 'active'
      and m.starts_at::date <= (select effective_week_date from pg_temp.verify_regrouping_apply_target)
      and g.name = (select plan_group_name from pg_temp.verify_regrouping_apply_target)
  ) as active_membership_from_effective_week,
  (
    select case when
      (select count(*) from public.regrouping_plan_groups where season_id = s.season_id) = 1
      and (select count(*) from public.regrouping_plan_assignments where season_id = s.season_id) = 1
      then 1 else 0 end
    from pg_temp.verify_regrouping_apply_season s
  ) as planned_rows_preserved,
  (
    select count(*)::integer
    from public.groups g
    where g.department_id = (select department_id from pg_temp.verify_regrouping_apply_target)
      and g.name = (select plan_group_name from pg_temp.verify_regrouping_apply_target)
      and g.active_from = (select effective_week_date from pg_temp.verify_regrouping_apply_target)
  ) as created_group_active_from_effective_week,
  (select affected_person_count from pg_temp.verify_regrouping_apply_season) as affected_person_count;

rollback;
