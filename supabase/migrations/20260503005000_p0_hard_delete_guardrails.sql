-- P0 hard-delete guardrails.
-- Keep tenant/org/calendar rows available for audit/history and use inactive/ended state instead.

set check_function_bodies = off;

alter table public.departments
  add column if not exists is_active boolean default true,
  add column if not exists ended_at timestamp with time zone;

update public.departments
set is_active = true
where is_active is null;

alter table public.departments
  alter column is_active set default true,
  alter column is_active set not null;

alter table public.groups
  add column if not exists ended_at timestamp with time zone;

update public.groups
set is_active = true
where is_active is null;

alter table public.groups
  alter column is_active set default true,
  alter column is_active set not null;

create index if not exists idx_departments_active_church
  on public.departments (church_id, is_active, name);

create index if not exists idx_groups_active_department
  on public.groups (department_id, is_active, name);

create or replace function public.handle_group_soft_end()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ended_at timestamp with time zone;
begin
  if NEW.is_active = true then
    NEW.ended_at := null;
    return NEW;
  end if;

  if OLD.is_active is distinct from NEW.is_active and NEW.is_active = false then
    v_ended_at := coalesce(NEW.ended_at, now());
    NEW.ended_at := v_ended_at;

    update public.group_members
    set is_active = false
    where group_id = NEW.id
      and is_active = true;

    update public.memberships
    set status = 'ended',
        ends_at = coalesce(ends_at, v_ended_at),
        updated_at = now()
    where group_id = NEW.id
      and status = 'active';

    update public.member_directory
    set group_name = null,
        left_at = coalesce(left_at, v_ended_at)
    where church_id = NEW.church_id
      and department_id = NEW.department_id
      and group_name = OLD.name
      and is_active = true;
  end if;

  return NEW;
end;
$$;

create or replace function public.handle_department_soft_end()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ended_at timestamp with time zone;
begin
  if NEW.is_active = true then
    NEW.ended_at := null;
    return NEW;
  end if;

  if OLD.is_active is distinct from NEW.is_active and NEW.is_active = false then
    v_ended_at := coalesce(NEW.ended_at, now());
    NEW.ended_at := v_ended_at;

    update public.groups
    set is_active = false,
        ended_at = coalesce(ended_at, v_ended_at)
    where department_id = NEW.id
      and is_active = true;

    update public.memberships
    set status = 'ended',
        ends_at = coalesce(ends_at, v_ended_at),
        updated_at = now()
    where department_id = NEW.id
      and status = 'active';

    update public.member_directory
    set is_active = false,
        left_at = coalesce(left_at, v_ended_at)
    where department_id = NEW.id
      and is_active = true;

    update public.profiles
    set department_id = null
    where department_id = NEW.id;
  end if;

  return NEW;
end;
$$;

drop trigger if exists before_group_soft_end on public.groups;
create trigger before_group_soft_end
before update of is_active on public.groups
for each row
execute function public.handle_group_soft_end();

drop trigger if exists before_department_soft_end on public.departments;
create trigger before_department_soft_end
before update of is_active on public.departments
for each row
execute function public.handle_department_soft_end();

create or replace view public.public_department_list as
select id, church_id, name
from public.departments
where is_active = true;
