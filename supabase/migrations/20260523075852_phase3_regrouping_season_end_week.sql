-- Phase 3 regrouping season period metadata.
-- Adds optional end_week_date so admins can describe the full season period
-- without changing live membership application semantics.

set check_function_bodies = off;

alter table public.regrouping_seasons
add column if not exists end_week_date date;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_seasons_end_week_sunday_check'
      and conrelid = 'public.regrouping_seasons'::regclass
  ) then
    alter table public.regrouping_seasons
    add constraint regrouping_seasons_end_week_sunday_check
      check (end_week_date is null or extract(dow from end_week_date) = 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'regrouping_seasons_period_order_check'
      and conrelid = 'public.regrouping_seasons'::regclass
  ) then
    alter table public.regrouping_seasons
    add constraint regrouping_seasons_period_order_check
      check (end_week_date is null or end_week_date >= effective_week_date);
  end if;
end $$;

drop function if exists public.create_regrouping_season(
  uuid,
  uuid,
  text,
  date,
  date
);

create or replace function public.create_regrouping_season(
  p_church_id uuid,
  p_department_id uuid,
  p_title text,
  p_effective_week_date date,
  p_end_week_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season_id uuid;
  v_title text := nullif(btrim(p_title), '');
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if not exists (
    select 1
    from public.departments d
    where d.id = p_department_id
      and d.church_id = p_church_id
  ) then
    raise exception 'department does not belong to church.';
  end if;

  if not (
    public.check_is_master()
    or public.is_admin_approved(p_church_id)
  ) then
    raise exception 'not allowed to create regrouping season.';
  end if;

  if v_title is null then
    raise exception 'title is required.';
  end if;

  if p_effective_week_date is null then
    raise exception 'effective_week_date is required.';
  end if;

  if extract(dow from p_effective_week_date)::integer <> 0 then
    raise exception 'effective_week_date must be a Sunday.';
  end if;

  if p_end_week_date is not null and extract(dow from p_end_week_date)::integer <> 0 then
    raise exception 'end_week_date must be a Sunday.';
  end if;

  if p_end_week_date is not null and p_end_week_date < p_effective_week_date then
    raise exception 'end_week_date must be on or after effective_week_date.';
  end if;

  insert into public.regrouping_seasons (
    church_id,
    department_id,
    title,
    effective_week_date,
    end_week_date,
    created_by
  )
  values (
    p_church_id,
    p_department_id,
    v_title,
    p_effective_week_date,
    p_end_week_date,
    auth.uid()
  )
  returning id into v_season_id;

  return v_season_id;
end;
$$;

create or replace function public.create_regrouping_season(
  p_church_id uuid,
  p_department_id uuid,
  p_title text,
  p_effective_week_date date
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.create_regrouping_season(
    p_church_id,
    p_department_id,
    p_title,
    p_effective_week_date,
    null::date
  );
$$;

drop function if exists public.update_regrouping_season(
  uuid,
  text,
  date,
  date
);

create or replace function public.update_regrouping_season(
  p_season_id uuid,
  p_title text,
  p_effective_week_date date,
  p_end_week_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
  v_title text := nullif(btrim(p_title), '');
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
    raise exception 'not allowed to update regrouping season.';
  end if;

  if v_season.status not in ('draft', 'ready') then
    raise exception 'only draft or ready regrouping seasons are editable.';
  end if;

  if v_title is null then
    raise exception 'title is required.';
  end if;

  if p_effective_week_date is null then
    raise exception 'effective_week_date is required.';
  end if;

  if extract(dow from p_effective_week_date)::integer <> 0 then
    raise exception 'effective_week_date must be a Sunday.';
  end if;

  if p_end_week_date is not null and extract(dow from p_end_week_date)::integer <> 0 then
    raise exception 'end_week_date must be a Sunday.';
  end if;

  if p_end_week_date is not null and p_end_week_date < p_effective_week_date then
    raise exception 'end_week_date must be on or after effective_week_date.';
  end if;

  update public.regrouping_seasons
  set title = v_title,
      effective_week_date = p_effective_week_date,
      end_week_date = p_end_week_date,
      updated_at = now()
  where id = p_season_id;
end;
$$;

create or replace function public.update_regrouping_season(
  p_season_id uuid,
  p_title text,
  p_effective_week_date date
)
returns void
language sql
security definer
set search_path = public
as $$
  select public.update_regrouping_season(
    p_season_id,
    p_title,
    p_effective_week_date,
    null::date
  );
$$;

grant execute on function public.create_regrouping_season(
  uuid,
  uuid,
  text,
  date,
  date
) to authenticated, service_role;

grant execute on function public.update_regrouping_season(
  uuid,
  text,
  date,
  date
) to authenticated, service_role;
