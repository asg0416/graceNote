#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

const args = process.argv.slice(2);

const getFlagValue = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const hasFlag = (flag) => args.includes(flag);

const dbUrlFile = getFlagValue("--db-url-file");
const targetName = getFlagValue("--name") || "이수진";
const targetPhone = getFlagValue("--phone") || "";
const applyKakaoReset = hasFlag("--apply-reset-kakao");
const confirmedDevReset = hasFlag("--confirm-dev-reset");

if (dbUrlFile && !existsSync(dbUrlFile)) {
  console.error(`DB URL file not found: ${dbUrlFile}`);
  process.exit(2);
}

const rawDbUrl = process.env.GRACENOTE_DEV_DB_URL
  || (dbUrlFile ? readFileSync(dbUrlFile, "utf8").trim() : "");

if (!rawDbUrl) {
  console.error("Provide GRACENOTE_DEV_DB_URL or --db-url-file <path>.");
  process.exit(2);
}

if (applyKakaoReset && !confirmedDevReset) {
  console.error("--apply-reset-kakao requires --confirm-dev-reset.");
  console.error("This tool is intended for the dev DB only.");
  process.exit(2);
}

const sqlString = (value) => `'${String(value).replaceAll("'", "''")}'`;

const auditSql = `
\\pset pager off
\\echo '## Target'
select
  ${sqlString(targetName)} as target_name,
  case
    when ${sqlString(targetPhone)} = '' then '(not provided)'
    else left(regexp_replace(${sqlString(targetPhone)}, '[^0-9]', '', 'g'), 3)
      || '****'
      || right(regexp_replace(${sqlString(targetPhone)}, '[^0-9]', '', 'g'), 4)
  end as target_phone_masked;

\\echo ''
\\echo '## Matching profiles'
with target as (
  select
    ${sqlString(targetName)}::text as full_name,
    nullif(regexp_replace(${sqlString(targetPhone)}::text, '[^0-9]', '', 'g'), '') as phone
),
matched_profiles as (
  select p.*
  from public.profiles p, target t
  where p.full_name = t.full_name
     or (t.phone is not null and regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = t.phone)
     or p.id in (
       select i.user_id
       from auth.identities i
       where i.provider = 'kakao'
     )
),
providers as (
  select
    i.user_id,
    string_agg(distinct i.provider, ', ' order by i.provider) as providers
  from auth.identities i
  group by i.user_id
)
select
  left(mp.id::text, 8) as profile,
  mp.full_name,
  case
    when mp.email is null or mp.email = '' then '(no email)'
    else left(mp.email, 1) || '***@' || split_part(mp.email, '@', 2)
  end as email,
  case
    when mp.phone is null or mp.phone = '' then '(no phone)'
    else left(regexp_replace(mp.phone, '[^0-9]', '', 'g'), 3)
      || '****'
      || right(regexp_replace(mp.phone, '[^0-9]', '', 'g'), 4)
  end as phone,
  coalesce(providers.providers, '(no auth identity)') as auth_providers,
  mp.role,
  mp.admin_status,
  mp.is_onboarding_complete,
  left(mp.person_id::text, 8) as person,
  coalesce(c.name, '(no church)') as church,
  coalesce(d.name, '(no department)') as department
from matched_profiles mp
left join providers on providers.user_id = mp.id
left join public.churches c on c.id = mp.church_id
left join public.departments d on d.id = mp.department_id
order by mp.full_name nulls last, mp.created_at nulls last;

\\echo ''
\\echo '## Matching auth identities'
with target as (
  select
    ${sqlString(targetName)}::text as full_name,
    nullif(regexp_replace(${sqlString(targetPhone)}::text, '[^0-9]', '', 'g'), '') as phone
),
matched_users as (
  select distinct u.*
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join auth.identities i on i.user_id = u.id
  cross join target t
  where p.full_name = t.full_name
     or (t.phone is not null and regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = t.phone)
     or i.provider = 'kakao'
)
select
  left(u.id::text, 8) as auth_user,
  coalesce(i.provider, '(none)') as provider,
  case
    when u.email is null or u.email = '' then '(no email)'
    else left(u.email, 1) || '***@' || split_part(u.email, '@', 2)
  end as email,
  u.created_at::date as created_date,
  u.last_sign_in_at::date as last_sign_in_date
from matched_users u
left join auth.identities i on i.user_id = u.id
order by u.created_at nulls last, provider;

\\echo ''
\\echo '## Person-level church records kept on reset'
with target as (
  select
    ${sqlString(targetName)}::text as full_name,
    nullif(regexp_replace(${sqlString(targetPhone)}::text, '[^0-9]', '', 'g'), '') as phone
),
candidate_people as (
  select distinct p.person_id
  from public.profiles p, target t
  where p.person_id is not null
    and (
      p.full_name = t.full_name
      or (t.phone is not null and regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = t.phone)
    )
  union
  select distinct md.person_id
  from public.member_directory md, target t
  where md.person_id is not null
    and (
      md.full_name = t.full_name
      or (t.phone is not null and regexp_replace(coalesce(md.phone, ''), '[^0-9]', '', 'g') = t.phone)
    )
)
select
  left(cp.person_id::text, 8) as person,
  count(distinct mp.id) as member_profile_rows,
  count(distinct m.id) as membership_rows,
  count(distinct a.id) as attendance_rows,
  count(distinct pe.id) as prayer_rows
from candidate_people cp
left join public.member_profiles mp on mp.person_id = cp.person_id
left join public.memberships m on m.person_id = cp.person_id
left join public.attendance a on a.person_id = cp.person_id
left join public.prayer_entries pe on pe.person_id = cp.person_id
group by cp.person_id
order by person;
`;

const resetSql = `
begin;

create temporary table if not exists pg_temp.kakao_smoke_profiles as
select p.id
from public.profiles p
where p.id in (
  select i.user_id
  from auth.identities i
  where i.provider = 'kakao'
)
and (
  p.full_name = ${sqlString(targetName)}
  or p.email is null
  or p.email = ''
);

delete from public.profiles
where id in (select id from pg_temp.kakao_smoke_profiles);

delete from auth.users
where id in (select id from pg_temp.kakao_smoke_profiles);

commit;

\\echo 'Reset kakao smoke auth/profile rows only. Church-owned person records were not deleted.'
`;

const result = spawnSync("docker", [
  "run",
  "--rm",
  "-i",
  "postgres:16-alpine",
  "psql",
  rawDbUrl,
  "-v",
  "ON_ERROR_STOP=1",
  "-P",
  "pager=off",
], {
  cwd: process.cwd(),
  encoding: "utf8",
  input: applyKakaoReset ? `${auditSql}\n${resetSql}\n${auditSql}` : auditSql,
  stdio: ["pipe", "pipe", "pipe"],
});

if (result.status !== 0) {
  console.error(result.stderr.trim());
  console.log(result.stdout.trim());
  process.exit(result.status ?? 1);
}

console.log(result.stdout.trim());
