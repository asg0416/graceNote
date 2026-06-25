-- Dev/staging rollback verifier for future regrouping drafts.
-- Future season drafts must not mutate live rows, and apply must be rejected
-- until the effective week arrives.

begin;

create temporary table pg_temp.verify_future_regrouping_target on commit drop as
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
  ((current_date - extract(dow from current_date)::integer)::date + interval '28 days')::date as future_week_date
from target_department td
cross join auth_context
cross join target_person tp;

create temporary table pg_temp.verify_future_regrouping_counts (
  label text primary key,
  groups_count bigint,
  member_directory_count bigint,
  group_members_count bigint,
  memberships_count bigint
) on commit drop;

insert into pg_temp.verify_future_regrouping_counts
select
  'before',
  (select count(*) from public.groups),
  (select count(*) from public.member_directory),
  (select count(*) from public.group_members),
  (select count(*) from public.memberships);

create temporary table pg_temp.verify_future_regrouping_season (
  season_id uuid,
  plan_group_count integer,
  assignment_count integer,
  apply_rejected integer default 0
) on commit drop;

insert into pg_temp.verify_future_regrouping_season (season_id)
select public.create_regrouping_season(
  church_id,
  department_id,
  'verify future regrouping draft',
  future_week_date
)
from pg_temp.verify_future_regrouping_target;

with saved as (
  select *
  from public.save_regrouping_season_draft(
    (select season_id from pg_temp.verify_future_regrouping_season),
    jsonb_build_array(
      jsonb_build_object(
        'id', 'verify-future-group',
        'name', 'verify future group',
        'sort_order', 1
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'group_id', 'verify-future-group',
        'person_id', (select person_id from pg_temp.verify_future_regrouping_target),
        'source_membership_id', (select source_membership_id from pg_temp.verify_future_regrouping_target),
        'source_member_directory_id', (select source_member_directory_id from pg_temp.verify_future_regrouping_target),
        'role_in_group', 'member',
        'sort_order', 1
      )
    )
  )
)
update pg_temp.verify_future_regrouping_season season
set
  plan_group_count = saved.plan_group_count,
  assignment_count = saved.assignment_count
from saved;

insert into pg_temp.verify_future_regrouping_counts
select
  'after_draft',
  (select count(*) from public.groups),
  (select count(*) from public.member_directory),
  (select count(*) from public.group_members),
  (select count(*) from public.memberships);

do $$
begin
  perform public.apply_regrouping_season(
    (select season_id from pg_temp.verify_future_regrouping_season)
  );

  raise exception 'future apply unexpectedly succeeded.';
exception
  when others then
    if position('future regrouping seasons cannot be applied before the effective week' in sqlerrm) = 0 then
      raise;
    end if;

    update pg_temp.verify_future_regrouping_season
    set apply_rejected = 1;
end;
$$;

select
  'regrouping_future_draft_safety' as check_name,
  (select plan_group_count from pg_temp.verify_future_regrouping_season) as plan_group_count,
  (select assignment_count from pg_temp.verify_future_regrouping_season) as assignment_count,
  (
    select case when
      before_counts.groups_count = after_counts.groups_count
      and before_counts.member_directory_count = after_counts.member_directory_count
      and before_counts.group_members_count = after_counts.group_members_count
      and before_counts.memberships_count = after_counts.memberships_count
    then 1 else 0 end
    from pg_temp.verify_future_regrouping_counts before_counts
    join pg_temp.verify_future_regrouping_counts after_counts
      on after_counts.label = 'after_draft'
    where before_counts.label = 'before'
  ) as live_counts_unchanged_after_draft,
  (select apply_rejected from pg_temp.verify_future_regrouping_season) as future_apply_rejected;

rollback;
