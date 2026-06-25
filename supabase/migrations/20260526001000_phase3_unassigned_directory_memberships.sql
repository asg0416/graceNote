-- Keep active department members visible when they are intentionally unassigned.
-- Legacy member_directory can represent "active in department, no group"; the
-- person-era memberships table must preserve that state as group_id = null.

set check_function_bodies = off;

create or replace function public.phase2_sync_member_directory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_person_id uuid;
  v_phone text;
  v_group_id uuid;
begin
  if new.church_id is null then
    return new;
  end if;

  v_person_id := public.phase2_upsert_person(
    new.church_id,
    new.person_id,
    new.profile_id,
    new.id,
    new.full_name,
    new.phone
  );
  v_phone := public.phase2_normalize_phone(new.phone);

  insert into public.person_identifiers (
    person_id,
    kind,
    value,
    source_table,
    source_id,
    is_primary
  )
  values (v_person_id, 'legacy_directory', new.id::text, 'member_directory', new.id, false)
  on conflict do nothing;

  if v_phone is not null then
    insert into public.person_identifiers (
      person_id,
      kind,
      value,
      source_table,
      source_id,
      is_primary
    )
    values (v_person_id, 'phone', v_phone, 'member_directory', new.id, false)
    on conflict do nothing;
  end if;

  insert into public.member_profiles (
    person_id,
    profile_id,
    member_directory_id,
    full_name,
    phone,
    avatar_url,
    family_name
  )
  values (
    v_person_id,
    new.profile_id,
    new.id,
    new.full_name,
    new.phone,
    new.avatar_url,
    new.family_name
  )
  on conflict (member_directory_id) do update set
    person_id = excluded.person_id,
    profile_id = excluded.profile_id,
    full_name = excluded.full_name,
    phone = excluded.phone,
    avatar_url = excluded.avatar_url,
    family_name = excluded.family_name,
    updated_at = now();

  select id into v_group_id
  from public.groups
  where church_id = new.church_id
    and department_id = new.department_id
    and name = new.group_name
  limit 1;

  if v_group_id is null
     or not exists (
       select 1
       from public.group_members gm
       where gm.member_directory_id = new.id
         and gm.is_active = true
     )
  then
    insert into public.memberships (
      person_id,
      church_id,
      department_id,
      group_id,
      role,
      status,
      starts_at,
      ends_at,
      legacy_member_directory_id
    )
    values (
      v_person_id,
      new.church_id,
      new.department_id,
      v_group_id,
      case when new.role_in_group = 'leader' then 'leader' else 'member' end,
      case when coalesce(new.is_active, true) then 'active' else 'inactive' end,
      coalesce(new.joined_at, new.created_at, now()),
      case when coalesce(new.is_active, true) then null else coalesce(new.left_at, now()) end,
      new.id
    )
    on conflict (legacy_member_directory_id)
      where legacy_group_member_id is null and legacy_member_directory_id is not null
    do update set
      person_id = excluded.person_id,
      church_id = excluded.church_id,
      department_id = excluded.department_id,
      group_id = excluded.group_id,
      role = excluded.role,
      status = excluded.status,
      ends_at = excluded.ends_at,
      updated_at = now();
  else
    update public.memberships
    set status = 'ended',
        ends_at = coalesce(ends_at, now()),
        updated_at = now()
    where legacy_member_directory_id = new.id
      and legacy_group_member_id is null
      and status = 'active';
  end if;

  return new;
end;
$$;

-- Repair existing active unassigned directory rows that were previously ended
-- in memberships, then add them back into current season plans as unassigned.
with repaired as (
  insert into public.memberships (
    person_id,
    church_id,
    department_id,
    group_id,
    role,
    status,
    starts_at,
    ends_at,
    legacy_member_directory_id
  )
  select
    public.phase2_upsert_person(
      md.church_id,
      md.person_id,
      md.profile_id,
      md.id,
      md.full_name,
      md.phone
    ) as person_id,
    md.church_id,
    md.department_id,
    null::uuid as group_id,
    case when md.role_in_group = 'leader' then 'leader' else 'member' end as role,
    'active' as status,
    coalesce(md.joined_at, md.created_at, now()) as starts_at,
    null::timestamptz as ends_at,
    md.id as legacy_member_directory_id
  from public.member_directory md
  where md.church_id is not null
    and md.department_id is not null
    and md.is_active is not false
    and nullif(btrim(coalesce(md.group_name, '')), '') is null
  on conflict (legacy_member_directory_id)
    where legacy_group_member_id is null and legacy_member_directory_id is not null
  do update set
    person_id = excluded.person_id,
    church_id = excluded.church_id,
    department_id = excluded.department_id,
    group_id = null,
    role = excluded.role,
    status = 'active',
    ends_at = null,
    updated_at = now()
  returning *
),
current_seasons as (
  select s.*
  from public.regrouping_seasons s
  where s.status = 'applied'
    and public.phase3_regrouping_season_is_current(
      s.effective_week_date,
      s.end_week_date
    )
),
missing_plan_rows as (
  select
    s.id as season_id,
    m.id as membership_id,
    m.legacy_member_directory_id,
    m.person_id,
    m.role,
    greatest(
      coalesce(public.phase3_week_start(m.starts_at::date), s.effective_week_date),
      s.effective_week_date
    ) as starts_week_date,
    s.end_week_date
  from repaired m
  join current_seasons s
    on s.church_id = m.church_id
   and s.department_id = m.department_id
  where m.status = 'active'
    and m.group_id is null
    and m.legacy_member_directory_id is not null
    and not exists (
      select 1
      from public.regrouping_plan_assignments rpa
      where rpa.season_id = s.id
        and rpa.person_id = m.person_id
    )
)
insert into public.regrouping_plan_assignments (
  season_id,
  plan_group_id,
  person_id,
  role_in_group,
  sort_order,
  source_membership_id,
  source_member_directory_id,
  starts_week_date,
  ends_week_date
)
select
  season_id,
  null::uuid,
  person_id,
  case when role = 'leader' then 'leader' else 'member' end,
  row_number() over (
    partition by season_id
    order by person_id
  )::integer - 1,
  membership_id,
  legacy_member_directory_id,
  starts_week_date,
  end_week_date
from missing_plan_rows
where starts_week_date <= coalesce(end_week_date, starts_week_date)
on conflict do nothing;
