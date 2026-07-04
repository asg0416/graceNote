-- Current-season saves can close stale active membership rows at the moment
-- just before the season effective week. If a duplicate/stale row already has
-- starts_at on the effective week, that produces ends_at < starts_at and trips
-- memberships_check. Clamp membership period writes at the table boundary so
-- every write path keeps the existing check constraint satisfied.

set check_function_bodies = off;

create or replace function public.clamp_membership_period_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.starts_at is null then
    if tg_op = 'UPDATE' then
      new.starts_at := coalesce(old.starts_at, now());
    else
      new.starts_at := now();
    end if;
  end if;

  if new.ends_at is not null and new.ends_at < new.starts_at then
    new.ends_at := new.starts_at;
  end if;

  return new;
end;
$$;

drop trigger if exists clamp_membership_period_before_write
on public.memberships;

create trigger clamp_membership_period_before_write
before insert or update of starts_at, ends_at, status
on public.memberships
for each row
execute function public.clamp_membership_period_before_write();

revoke execute on function public.clamp_membership_period_before_write()
from public, anon, authenticated;

grant execute on function public.clamp_membership_period_before_write()
to service_role;
