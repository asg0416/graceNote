#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const getFlagValue = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const dbUrlFile = getFlagValue('--db-url-file');
const shouldApplyExtraEnd = args.includes('--apply-extra-live-end');
const shouldApplySyncToPlan = args.includes('--apply-sync-to-plan');
const shouldApply = shouldApplyExtraEnd || shouldApplySyncToPlan;
const confirmedDevRepair = args.includes('--confirm-dev-repair');
const allowNonEftdf = args.includes('--allow-non-eftdf-dev');
const personName = getFlagValue('--person-name');

const knownProdProjectRefs = [
  'eejqiddsdovrabcsxznu',
];

if (dbUrlFile && !existsSync(dbUrlFile)) {
  console.error(`DB URL file not found: ${dbUrlFile}`);
  process.exit(2);
}

const dbUrl = process.env.GRACENOTE_VERIFY_DB_URL
  || (dbUrlFile ? readFileSync(dbUrlFile, 'utf8').trim() : '');

if (!dbUrl) {
  console.error('Provide GRACENOTE_VERIFY_DB_URL or --db-url-file <path>.');
  process.exit(2);
}

if (knownProdProjectRefs.some((projectRef) => dbUrl.includes(projectRef))) {
  console.error('Refusing to run against the known production project ref.');
  process.exit(2);
}

if (shouldApply && !confirmedDevRepair) {
  console.error('Refusing to mutate data without --confirm-dev-repair.');
  process.exit(2);
}

if (shouldApply && !allowNonEftdf && !dbUrl.includes('eftdf') && !dbUrl.includes('localhost')) {
  console.error('Refusing repair because DB URL does not look like the eftdf dev/local project.');
  console.error('Pass --allow-non-eftdf-dev only for an explicitly confirmed dev/staging clone.');
  process.exit(2);
}

const sqlLiteral = (value) => `'${String(value).replaceAll("'", "''")}'`;

const personNameFilter = personName
  ? `and coalesce(p.display_name, md.full_name, '(unknown)') = ${sqlLiteral(personName)}`
  : '';

const buildSql = ({ applyExtraEnd, applySyncToPlan }) => String.raw`
\pset pager off
\pset null '(null)'

drop table if exists
  audit_current_seasons,
  audit_plan_current_assignments,
  audit_live_current_memberships,
  audit_extra_live_memberships,
  audit_missing_live_memberships,
  audit_empty_plan_groups_with_live;

create temporary table audit_current_seasons as
  select *
  from public.regrouping_seasons s
  where s.status = 'applied'
    and s.effective_week_date <= current_date
    and (s.end_week_date is null or s.end_week_date + 6 >= current_date);

create temporary table audit_plan_current_assignments as
  select
    s.id as season_id,
    s.church_id,
    s.department_id,
    s.title as season_title,
    rpa.id as assignment_id,
    rpa.source_member_directory_id,
    rpa.person_id,
    coalesce(p.display_name, md.full_name, '(unknown)') as person_name,
    rpg.id as plan_group_id,
    rpg.source_group_id,
    rpg.name as plan_group_name,
    rpa.role_in_group,
    rpa.starts_week_date,
    rpa.ends_week_date
  from audit_current_seasons s
  join public.regrouping_plan_assignments rpa
    on rpa.season_id = s.id
  left join public.regrouping_plan_groups rpg
    on rpg.id = rpa.plan_group_id
  left join public.people p
    on p.id = rpa.person_id
  left join public.member_directory md
    on md.id = rpa.source_member_directory_id
  where coalesce(rpa.starts_week_date, s.effective_week_date) <= current_date
    and (rpa.ends_week_date is null or rpa.ends_week_date + 6 >= current_date)
    ${personNameFilter};

create temporary table audit_live_current_memberships as
  select
    s.id as season_id,
    s.church_id,
    s.department_id,
    s.title as season_title,
    m.id as membership_id,
    m.person_id,
    coalesce(p.display_name, md.full_name, '(unknown)') as person_name,
    m.group_id,
    g.name as live_group_name,
    m.role as role_in_group,
    public.phase3_week_start(m.starts_at::date) as live_start_week,
    case when m.ends_at is null then null else public.phase3_week_start(m.ends_at::date) end as live_end_week,
    m.starts_at,
    m.ends_at
  from audit_current_seasons s
  join public.memberships m
    on m.church_id = s.church_id
   and m.department_id = s.department_id
   and m.status = 'active'
  left join public.groups g
    on g.id = m.group_id
  left join public.people p
    on p.id = m.person_id
  left join public.member_directory md
    on md.id = m.legacy_member_directory_id
  where coalesce(m.starts_at::date, s.effective_week_date) <= current_date
    and (m.ends_at is null or m.ends_at::date >= current_date)
    and (g.id is null or coalesce(g.active_from, s.effective_week_date) <= current_date)
    and (g.id is null or g.ended_at is null or g.ended_at::date >= current_date)
    ${personNameFilter};

create temporary table audit_extra_live_memberships as
  select live.*
  from audit_live_current_memberships live
  where not exists (
    select 1
    from audit_plan_current_assignments plan
    where plan.season_id = live.season_id
      and plan.person_id = live.person_id
      and (
        (plan.source_group_id is null and live.group_id is null)
        or plan.source_group_id = live.group_id
      )
  );

create temporary table audit_missing_live_memberships as
  select plan.*
  from audit_plan_current_assignments plan
  where not exists (
    select 1
    from audit_live_current_memberships live
    where live.season_id = plan.season_id
      and live.person_id = plan.person_id
      and (
        (plan.source_group_id is null and live.group_id is null)
        or plan.source_group_id = live.group_id
      )
  );

create temporary table audit_empty_plan_groups_with_live as
  select
    s.title as season_title,
    rpg.name as plan_group_name,
    rpg.source_group_id,
    count(live.membership_id)::integer as live_membership_count
  from audit_current_seasons s
  join public.regrouping_plan_groups rpg
    on rpg.season_id = s.id
  join audit_live_current_memberships live
    on live.season_id = s.id
   and live.group_id = rpg.source_group_id
  where not exists (
    select 1
    from audit_plan_current_assignments plan
    where plan.season_id = s.id
      and plan.source_group_id = rpg.source_group_id
  )
  group by s.title, rpg.name, rpg.source_group_id;

select 'current_seasons' as check_name, count(*)::text as result from audit_current_seasons
union all
select 'current_plan_assignments', count(*)::text from audit_plan_current_assignments
union all
select 'current_live_memberships', count(*)::text from audit_live_current_memberships
union all
select 'extra_live_memberships_not_in_plan', count(*)::text from audit_extra_live_memberships
union all
select 'missing_live_memberships_from_plan', count(*)::text from audit_missing_live_memberships
union all
select 'empty_plan_groups_with_live_memberships', count(*)::text from audit_empty_plan_groups_with_live;

select
  'extra_live_membership' as issue_type,
  season_title,
  person_name,
  live_group_name,
  role_in_group,
  live_start_week,
  live_end_week,
  membership_id
from audit_extra_live_memberships
order by season_title, person_name, live_group_name
limit 100;

select
  'missing_live_membership' as issue_type,
  season_title,
  person_name,
  plan_group_name,
  role_in_group,
  starts_week_date,
  ends_week_date,
  assignment_id
from audit_missing_live_memberships
order by season_title, person_name, plan_group_name
limit 100;

select
  'empty_plan_group_with_live' as issue_type,
  season_title,
  plan_group_name,
  live_membership_count
from audit_empty_plan_groups_with_live
order by season_title, plan_group_name
limit 100;

${applyExtraEnd || applySyncToPlan ? String.raw`
update public.memberships m
set status = 'ended',
    ends_at = greatest(
      coalesce(m.starts_at, now()),
      least(coalesce(m.ends_at, now()), now())
    ),
    updated_at = now()
from audit_extra_live_memberships extra
where extra.membership_id = m.id;

select 'repaired_extra_live_memberships' as repair_name, count(*)::text as result
from audit_extra_live_memberships;
` : ''}

${applySyncToPlan ? String.raw`
drop table if exists audit_missing_existing_targets;

create temporary table audit_missing_existing_targets as
  select distinct on (missing.assignment_id)
    missing.assignment_id,
    m.id as membership_id
  from audit_missing_live_memberships missing
  join public.memberships m
    on m.church_id = missing.church_id
   and m.department_id = missing.department_id
   and m.person_id = missing.person_id
   and (
     (missing.source_group_id is null and m.group_id is null)
     or missing.source_group_id = m.group_id
   )
  order by
    missing.assignment_id,
    case when m.status = 'ended' then 0 when m.status = 'inactive' then 1 else 2 end,
    m.updated_at desc nulls last,
    m.starts_at desc nulls last,
    m.id;

update public.memberships m
set status = 'active',
    role = case when missing.role_in_group = 'leader' then 'leader' else 'member' end,
    starts_at = missing.starts_week_date::timestamp with time zone,
    ends_at = case
      when missing.ends_week_date is null then null
      else missing.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second'
    end,
    legacy_member_directory_id = coalesce(m.legacy_member_directory_id, missing.source_member_directory_id),
    updated_at = now()
from audit_missing_existing_targets target
join audit_missing_live_memberships missing
  on missing.assignment_id = target.assignment_id
where m.id = target.membership_id;

insert into public.memberships (
  person_id,
  church_id,
  department_id,
  group_id,
  role,
  status,
  starts_at,
  ends_at,
  legacy_member_directory_id,
  created_at,
  updated_at
)
select
  missing.person_id,
  missing.church_id,
  missing.department_id,
  missing.source_group_id,
  case when missing.role_in_group = 'leader' then 'leader' else 'member' end,
  'active',
  missing.starts_week_date::timestamp with time zone,
  case
    when missing.ends_week_date is null then null
    else missing.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second'
  end,
  missing.source_member_directory_id,
  now(),
  now()
from audit_missing_live_memberships missing
where not exists (
    select 1
    from audit_missing_existing_targets target
    where target.assignment_id = missing.assignment_id
  )
  and not exists (
    select 1
    from public.memberships m
    where m.church_id = missing.church_id
      and m.department_id = missing.department_id
      and m.person_id = missing.person_id
      and (
        (missing.source_group_id is null and m.group_id is null)
        or missing.source_group_id = m.group_id
      )
      and m.status = 'active'
  );

select 'synced_missing_live_memberships_to_plan' as repair_name, count(*)::text as result
from audit_missing_live_memberships;
` : ''}
`;

const runSql = (label, sql) => {
  console.log(`\n## ${label}`);
  const result = spawnSync('docker', [
    'run',
    '--rm',
    '-i',
    'postgres:16',
    'psql',
    dbUrl,
    '-v',
    'ON_ERROR_STOP=1',
    '-P',
    'pager=off',
  ], {
    cwd: process.cwd(),
    encoding: 'utf8',
    input: sql,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  if (result.status !== 0) {
    console.error(result.stderr.trim());
    console.log(result.stdout.trim());
    process.exit(result.status ?? 1);
  }

  console.log(result.stdout.trim() || '(0 rows)');
};

runSql('before regrouping live/plan audit', buildSql({ applyExtraEnd: false, applySyncToPlan: false }));

if (shouldApply) {
  runSql(
    shouldApplySyncToPlan ? 'apply dev live-to-plan repair' : 'apply dev extra-live repair',
    buildSql({ applyExtraEnd: shouldApplyExtraEnd, applySyncToPlan: shouldApplySyncToPlan })
  );
  runSql('after regrouping live/plan audit', buildSql({ applyExtraEnd: false, applySyncToPlan: false }));
} else {
  console.log('\nDry-run only. To repair dev extra live memberships, add --apply-extra-live-end --confirm-dev-repair.');
  console.log('To sync dev live memberships to current season plan, add --apply-sync-to-plan --confirm-dev-repair.');
}
