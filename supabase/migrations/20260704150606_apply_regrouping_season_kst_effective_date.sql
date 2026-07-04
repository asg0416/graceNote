-- Use the church's operational date (KST) when deciding whether a regrouping
-- season has reached its effective week. Supabase/Postgres current_date is UTC
-- in production, which blocks Sunday 00:00-08:59 KST season applications.

set check_function_bodies = off;

create or replace function public.apply_regrouping_season(p_season_id uuid)
returns table(
  created_group_count integer,
  ended_group_count integer,
  created_membership_count integer,
  ended_membership_count integer,
  affected_person_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_groups jsonb := '[]'::jsonb;
  v_assignments jsonb := '[]'::jsonb;
  v_ended_group_count integer := 0;
  v_ended_membership_count integer := 0;
  v_saved_count integer := 0;
begin
  select *
  into v_season
  from public.regrouping_seasons
  where id = p_season_id
  for update;

  if v_season.id is null then
    raise exception 'regrouping season not found.';
  end if;

  if not (
    public.check_is_master()
    or public.is_admin_approved(v_season.church_id)
  ) then
    raise exception 'not allowed to apply regrouping season.';
  end if;

  if v_season.status = 'applied' then
    raise exception 'regrouping season already applied.';
  end if;

  if v_season.status in ('cancelled', 'archived') then
    raise exception 'cancelled or archived regrouping seasons cannot be applied.';
  end if;

  if v_season.effective_week_date > (now() at time zone 'Asia/Seoul')::date then
    raise exception 'future regrouping seasons cannot be applied before the effective week.';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', coalesce(rpg.source_group_id::text, 'plan-' || rpg.id::text),
      'source_group_id', rpg.source_group_id,
      'name', rpg.name,
      'color_hex', rpg.color_hex,
      'sort_order', rpg.sort_order,
      'leader_person_id', rpg.leader_person_id
    )
    order by rpg.sort_order, rpg.name
  ), '[]'::jsonb)
  into v_groups
  from public.regrouping_plan_groups rpg
  where rpg.season_id = p_season_id
    and rpg.plan_status = 'active';

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', rpa.source_member_directory_id,
      'group_id', case
        when rpg.id is null then null
        else coalesce(rpg.source_group_id::text, 'plan-' || rpg.id::text)
      end,
      'full_name', coalesce(nullif(md.full_name, ''), nullif(mp.full_name, ''), nullif(p.display_name, ''), '이름 없음'),
      'phone', coalesce(nullif(md.phone, ''), nullif(mp.phone, ''), nullif(p.normalized_phone, ''), ''),
      'role_in_group', case when rpa.role_in_group = 'leader' then 'leader' else 'member' end,
      'family_name', md.family_name,
      'spouse_name', md.spouse_name,
      'children_info', md.children_info,
      'birth_date', md.birth_date,
      'wedding_anniversary', md.wedding_anniversary,
      'notes', md.notes,
      'avatar_url', coalesce(md.avatar_url, mp.avatar_url),
      'person_id', rpa.person_id,
      'phase2_person_id', rpa.person_id,
      'phase2_membership_id', rpa.source_membership_id,
      'profile_id', coalesce(md.profile_id, mp.profile_id),
      'sort_order', rpa.sort_order
    )
    order by rpg.sort_order nulls last, rpa.sort_order
  ), '[]'::jsonb)
  into v_assignments
  from public.regrouping_plan_assignments rpa
  left join public.regrouping_plan_groups rpg
    on rpg.id = rpa.plan_group_id
   and rpg.plan_status = 'active'
  join public.people p
    on p.id = rpa.person_id
  left join public.member_directory md
    on md.id = rpa.source_member_directory_id
  left join lateral (
    select mp.*
    from public.member_profiles mp
    where mp.person_id = rpa.person_id
    order by
      case when mp.member_directory_id = rpa.source_member_directory_id then 0 else 1 end,
      mp.updated_at desc nulls last,
      mp.created_at desc
    limit 1
  ) mp on true
  where rpa.season_id = p_season_id;

  select count(*)::integer
  into v_ended_group_count
  from public.groups g
  where g.church_id = v_season.church_id
    and g.department_id = v_season.department_id
    and g.is_active is not false
    and not exists (
      select 1
      from public.regrouping_plan_groups rpg
      where rpg.season_id = p_season_id
        and rpg.source_group_id = g.id
        and rpg.plan_status = 'active'
    );

  select count(*)::integer
  into v_ended_membership_count
  from public.memberships m
  where m.church_id = v_season.church_id
    and m.department_id = v_season.department_id
    and m.status = 'active'
    and not exists (
      select 1
      from public.regrouping_plan_assignments rpa
      where rpa.season_id = p_season_id
        and rpa.person_id = m.person_id
    );

  with saved as (
    select *
    from public.save_regrouping_memberships(
      v_season.church_id,
      v_season.department_id,
      v_groups,
      v_assignments,
      v_season.effective_week_date
    )
  )
  select count(*)::integer
  into v_saved_count
  from saved;

  update public.regrouping_seasons
  set status = 'applied',
      applied_at = now(),
      applied_by = auth.uid(),
      updated_at = now()
  where id = p_season_id;

  return query
  select
    (
      select count(*)::integer
      from public.regrouping_plan_groups rpg
      where rpg.season_id = p_season_id
        and rpg.source_group_id is null
        and rpg.plan_status = 'active'
    ),
    v_ended_group_count,
    v_saved_count,
    v_ended_membership_count,
    (
      select count(distinct rpa.person_id)::integer
      from public.regrouping_plan_assignments rpa
      where rpa.season_id = p_season_id
    );
end;
$$;

grant execute on function public.apply_regrouping_season(uuid) to authenticated, service_role;
