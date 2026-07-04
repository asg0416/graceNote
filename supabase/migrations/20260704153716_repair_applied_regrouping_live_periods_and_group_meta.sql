-- Keep the live state in sync after a regrouping season is applied.
--
-- The apply RPC creates/updates live groups and memberships through the generic
-- regrouping save RPC. That path can leave newly created live groups without the
-- season plan's new-family metadata, and old active membership rows whose
-- ends_at is before the applied season can still be selected by status-only
-- readers. Repair both for already-applied current seasons and install an
-- after-apply trigger so future season applications do not regress.

set check_function_bodies = off;

create or replace function public.repair_applied_regrouping_live_state(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  select *
  into v_season
  from public.regrouping_seasons
  where id = p_season_id;

  if v_season.id is null then
    raise exception 'regrouping season not found.';
  end if;

  if not (
    session_user in ('postgres', 'service_role', 'supabase_admin')
    or coalesce(auth.role(), '') = 'service_role'
    or public.check_is_master()
    or public.is_admin_approved(v_season.church_id)
  ) then
    raise exception 'not allowed to repair applied regrouping season.';
  end if;

  create temporary table if not exists pg_temp.regrouping_live_group_resolution (
    plan_group_id uuid primary key,
    live_group_id uuid not null,
    plan_status text,
    starts_week_date date,
    ends_week_date date,
    is_new_member_group boolean,
    climbing_threshold integer
  ) on commit drop;

  truncate table pg_temp.regrouping_live_group_resolution;

  insert into pg_temp.regrouping_live_group_resolution (
    plan_group_id,
    live_group_id,
    plan_status,
    starts_week_date,
    ends_week_date,
    is_new_member_group,
    climbing_threshold
  )
  select
    rpg.id,
    coalesce(rpg.source_group_id, live_group.id),
    coalesce(nullif(rpg.plan_status, ''), 'active'),
    coalesce(rpg.starts_week_date, v_season.effective_week_date),
    rpg.ends_week_date,
    coalesce(rpg.is_new_member_group, false),
    case
      when coalesce(rpg.is_new_member_group, false) then coalesce(rpg.climbing_threshold, 4)
      else null
    end
  from public.regrouping_plan_groups rpg
  left join public.groups live_group
    on live_group.church_id = v_season.church_id
   and live_group.department_id = v_season.department_id
   and live_group.name = rpg.name
  where rpg.season_id = p_season_id
    and coalesce(rpg.source_group_id, live_group.id) is not null
  on conflict (plan_group_id) do update
  set live_group_id = excluded.live_group_id,
      plan_status = excluded.plan_status,
      starts_week_date = excluded.starts_week_date,
      ends_week_date = excluded.ends_week_date,
      is_new_member_group = excluded.is_new_member_group,
      climbing_threshold = excluded.climbing_threshold;

  update public.regrouping_plan_groups rpg
  set source_group_id = resolved.live_group_id
  from pg_temp.regrouping_live_group_resolution resolved
  where rpg.id = resolved.plan_group_id
    and rpg.source_group_id is distinct from resolved.live_group_id;

  update public.groups g
  set is_new_member_group = resolved.is_new_member_group,
      climbing_threshold = resolved.climbing_threshold,
      active_from = case
        when resolved.plan_status = 'active' then resolved.starts_week_date
        when g.active_from is null then resolved.starts_week_date
        else g.active_from
      end,
      is_active = (resolved.plan_status = 'active'),
      ended_at = case
        when resolved.plan_status = 'ended' and resolved.ends_week_date is not null
          then resolved.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second'
        when resolved.plan_status = 'active' then null
        else g.ended_at
      end
  from pg_temp.regrouping_live_group_resolution resolved
  where g.id = resolved.live_group_id
    and g.church_id = v_season.church_id
    and g.department_id = v_season.department_id;

  create temporary table if not exists pg_temp.regrouping_live_membership_targets (
    membership_id uuid primary key,
    starts_week_date date not null,
    ends_week_date date
  ) on commit drop;

  truncate table pg_temp.regrouping_live_membership_targets;

  insert into pg_temp.regrouping_live_membership_targets (
    membership_id,
    starts_week_date,
    ends_week_date
  )
  select
    ranked.membership_id,
    ranked.starts_week_date,
    ranked.ends_week_date
  from (
    select
      m.id as membership_id,
      coalesce(rpa.starts_week_date, resolved.starts_week_date, v_season.effective_week_date) as starts_week_date,
      coalesce(rpa.ends_week_date, resolved.ends_week_date, v_season.end_week_date) as ends_week_date,
      row_number() over (
        partition by rpa.id
        order by
          case when m.legacy_member_directory_id = rpa.source_member_directory_id then 0 else 1 end,
          case when m.status = 'active' then 0 else 1 end,
          m.updated_at desc nulls last,
          m.starts_at desc nulls last,
          m.id
      ) as rn
    from public.regrouping_plan_assignments rpa
    join pg_temp.regrouping_live_group_resolution resolved
      on resolved.plan_group_id = rpa.plan_group_id
     and resolved.plan_status = 'active'
    join public.memberships m
      on m.church_id = v_season.church_id
     and m.department_id = v_season.department_id
     and m.person_id = rpa.person_id
     and m.group_id = resolved.live_group_id
    where rpa.season_id = p_season_id
      and rpa.plan_group_id is not null
  ) ranked
  where ranked.rn = 1
  on conflict (membership_id) do update
  set starts_week_date = excluded.starts_week_date,
      ends_week_date = excluded.ends_week_date;

  update public.memberships m
  set starts_at = targets.starts_week_date::timestamp with time zone,
      ends_at = case
        when targets.ends_week_date is not null
          then targets.ends_week_date::timestamp with time zone + interval '7 days' - interval '1 second'
        else null
      end,
      status = case
        when targets.ends_week_date is not null
          and targets.ends_week_date < public.phase3_week_start(v_today)
          then 'ended'
        else 'active'
      end,
      updated_at = now()
  from pg_temp.regrouping_live_membership_targets targets
  where m.id = targets.membership_id;

  update public.memberships m
  set status = 'ended',
      ends_at = least(
        coalesce(m.ends_at, v_season.effective_week_date::timestamp with time zone - interval '1 second'),
        v_season.effective_week_date::timestamp with time zone - interval '1 second'
      ),
      updated_at = now()
  where m.church_id = v_season.church_id
    and m.department_id = v_season.department_id
    and m.status = 'active'
    and m.ends_at is not null
    and m.ends_at < v_season.effective_week_date::timestamp with time zone
    and not exists (
      select 1
      from pg_temp.regrouping_live_membership_targets targets
      where targets.membership_id = m.id
    );
end;
$$;

create or replace function public.repair_applied_regrouping_live_state_after_apply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'applied' and old.status is distinct from 'applied' then
    perform public.repair_applied_regrouping_live_state(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists repair_applied_regrouping_live_state_after_apply
on public.regrouping_seasons;

create trigger repair_applied_regrouping_live_state_after_apply
after update of status
on public.regrouping_seasons
for each row
execute function public.repair_applied_regrouping_live_state_after_apply();

do $$
declare
  v_season_id uuid;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  for v_season_id in
    select id
    from public.regrouping_seasons
    where status = 'applied'
      and effective_week_date <= v_today
      and (end_week_date is null or end_week_date + 6 >= v_today)
  loop
    perform public.repair_applied_regrouping_live_state(v_season_id);
  end loop;
end $$;

revoke execute on function public.repair_applied_regrouping_live_state(uuid)
from public, anon;

grant execute on function public.repair_applied_regrouping_live_state(uuid)
to authenticated, service_role;
