#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const getFlagValue = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const dbUrlFile = getFlagValue('--db-url-file');

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

const sql = String.raw`
\pset pager off
\pset null '(null)'

drop table if exists
  verify_extra_live_memberships,
  verify_group_period_issues,
  verify_plan_group_rows,
  verify_member_period_issues,
  verify_plan_member_rows,
  verify_current_seasons;

create temporary table verify_current_seasons as
  select *
  from public.regrouping_seasons s
  where s.status = 'applied'
    and s.effective_week_date <= current_date
    and (s.end_week_date is null or s.end_week_date + 6 >= current_date);

create temporary table verify_plan_member_rows as
  select
    s.id as season_id,
    s.title as season_title,
    s.effective_week_date as season_start,
    s.end_week_date as season_end,
    rpa.id as assignment_id,
    rpa.person_id,
    coalesce(p.display_name, md.full_name, '(unknown)') as person_name,
    rpg.name as plan_group_name,
    rpg.source_group_id,
    rpa.starts_week_date as plan_start,
    rpa.ends_week_date as plan_end,
    m.id as live_membership_id,
    m.status as live_status,
    public.phase3_week_start(m.starts_at::date) as live_start_week,
    case when m.ends_at is null then null else public.phase3_week_start(m.ends_at::date) end as live_end_week
  from verify_current_seasons s
  join public.regrouping_plan_assignments rpa on rpa.season_id = s.id
  left join public.regrouping_plan_groups rpg on rpg.id = rpa.plan_group_id
  left join public.people p on p.id = rpa.person_id
  left join public.member_directory md on md.id = rpa.source_member_directory_id
  left join lateral (
    select m.*
    from public.memberships m
    where m.church_id = s.church_id
      and m.department_id = s.department_id
      and m.person_id = rpa.person_id
      and (
        (rpg.source_group_id is null and m.group_id is null)
        or m.group_id = rpg.source_group_id
      )
    order by
      case when m.status = 'active' then 0 else 1 end,
      m.updated_at desc nulls last,
      m.starts_at desc nulls last,
      m.id
    limit 1
  ) m on true
;

create temporary table verify_member_period_issues as
  select *
  from verify_plan_member_rows
  where live_membership_id is null
     or (
       plan_start > season_start
       and live_start_week is distinct from plan_start
     )
     or (
       plan_start <= season_start
       and (live_start_week is null or live_start_week > plan_start)
     )
     or (
       plan_end is not null
       and (season_end is null or plan_end < season_end)
       and live_end_week is distinct from plan_end
     );

create temporary table verify_plan_group_rows as
  select
    s.id as season_id,
    s.title as season_title,
    s.effective_week_date as season_start,
    s.end_week_date as season_end,
    rpg.id as plan_group_id,
    rpg.name as plan_group_name,
    rpg.source_group_id,
    rpg.plan_status,
    rpg.starts_week_date as plan_start,
    rpg.ends_week_date as plan_end,
    public.phase3_week_start(g.active_from) as live_start_week,
    case when g.ended_at is null then null else public.phase3_week_start(g.ended_at::date) end as live_end_week,
    g.is_active as live_is_active
  from verify_current_seasons s
  join public.regrouping_plan_groups rpg on rpg.season_id = s.id
  left join public.groups g on g.id = rpg.source_group_id
  where rpg.source_group_id is not null;

create temporary table verify_group_period_issues as
  select *
  from verify_plan_group_rows
  where (
       plan_start > season_start
       and live_start_week is distinct from plan_start
     )
     or (
       plan_start <= season_start
       and (live_start_week is null or live_start_week > plan_start)
     )
     or (
       plan_status = 'ended'
       and plan_end is not null
       and live_end_week is distinct from plan_end
     );

create temporary table verify_extra_live_memberships as
  select
    s.title as season_title,
    coalesce(p.display_name, md.full_name, '(unknown)') as person_name,
    g.name as live_group_name,
    m.id as live_membership_id,
    m.group_id,
    public.phase3_week_start(m.starts_at::date) as live_start_week,
    case when m.ends_at is null then null else public.phase3_week_start(m.ends_at::date) end as live_end_week
  from verify_current_seasons s
  join public.memberships m
    on m.church_id = s.church_id
   and m.department_id = s.department_id
   and m.status = 'active'
  left join public.people p on p.id = m.person_id
  left join public.member_directory md on md.id = m.legacy_member_directory_id
  left join public.groups g on g.id = m.group_id
  where not exists (
    select 1
    from public.regrouping_plan_assignments rpa
    left join public.regrouping_plan_groups rpg on rpg.id = rpa.plan_group_id
    where rpa.season_id = s.id
      and rpa.person_id = m.person_id
      and (
        (rpg.source_group_id is null and m.group_id is null)
        or rpg.source_group_id = m.group_id
      )
  );

select 'current_seasons' as check_name, count(*)::text as result
from verify_current_seasons
union all
select 'member_period_issues', count(*)::text
from verify_member_period_issues
union all
select 'group_period_issues', count(*)::text
from verify_group_period_issues
union all
select 'extra_live_memberships', count(*)::text
from verify_extra_live_memberships;

select
  'member_period_issue_detail' as detail_type,
  season_title,
  person_name,
  plan_group_name,
  plan_start,
  live_start_week,
  plan_end,
  live_end_week,
  live_status
from verify_member_period_issues
order by season_title, person_name, plan_group_name
limit 50;

select
  'group_period_issue_detail' as detail_type,
  season_title,
  plan_group_name,
  plan_status,
  plan_start,
  live_start_week,
  plan_end,
  live_end_week,
  live_is_active
from verify_group_period_issues
order by season_title, plan_group_name
limit 50;

select
  'extra_live_membership_detail' as detail_type,
  season_title,
  person_name,
  live_group_name,
  live_start_week,
  live_end_week,
  live_membership_id
from verify_extra_live_memberships
order by season_title, person_name, live_group_name nulls first
limit 50;
`;

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

console.log(result.stdout.trim());
