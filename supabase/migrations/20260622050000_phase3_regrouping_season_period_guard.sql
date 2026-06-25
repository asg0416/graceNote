-- Prevent overlapping regrouping seasons in the same church + department.
-- Existing rows are not validated immediately; this guard applies to future writes.

create or replace function public.phase3_guard_regrouping_season_period()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v_existing_title text;
begin
    if new.status is null or new.status not in ('draft', 'ready', 'applied', 'archived') then
        return new;
    end if;

    if new.church_id is null or new.department_id is null then
        raise exception 'regrouping season requires church and department.';
    end if;

    if new.effective_week_date is null then
        raise exception 'regrouping season requires effective_week_date.';
    end if;

    if extract(dow from new.effective_week_date)::int <> 0 then
        raise exception 'regrouping season effective_week_date must be a Sunday.';
    end if;

    if new.end_week_date is not null then
        if extract(dow from new.end_week_date)::int <> 0 then
            raise exception 'regrouping season end_week_date must be a Sunday.';
        end if;

        if new.end_week_date < new.effective_week_date then
            raise exception 'regrouping season end_week_date must be on or after effective_week_date.';
        end if;
    end if;

    select s.title
      into v_existing_title
      from public.regrouping_seasons s
     where s.church_id = new.church_id
       and s.department_id = new.department_id
       and s.status in ('draft', 'ready', 'applied', 'archived')
       and s.id <> new.id
       and s.effective_week_date <= coalesce(new.end_week_date, '9999-12-31'::date)
       and coalesce(s.end_week_date, '9999-12-31'::date) >= new.effective_week_date
     order by s.effective_week_date desc
     limit 1;

    if v_existing_title is not null then
        raise exception 'regrouping season period overlaps existing season: %', v_existing_title;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_phase3_guard_regrouping_season_period on public.regrouping_seasons;

create trigger trg_phase3_guard_regrouping_season_period
before insert or update of church_id, department_id, status, effective_week_date, end_week_date
on public.regrouping_seasons
for each row
execute function public.phase3_guard_regrouping_season_period();
