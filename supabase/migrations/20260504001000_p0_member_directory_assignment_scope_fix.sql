-- Keep inactive member_directory rows from blocking active assignment uniqueness,
-- and scope phone uniqueness to the current church's active directory rows.

set check_function_bodies = off;

create or replace function public.release_inactive_member_directory_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.is_active = false then
    NEW.group_name := null;
    NEW.left_at := coalesce(NEW.left_at, now());
  end if;

  return NEW;
end;
$$;

drop trigger if exists before_member_directory_inactive_assignment_release on public.member_directory;
create trigger before_member_directory_inactive_assignment_release
before update of is_active on public.member_directory
for each row
when (NEW.is_active = false)
execute function public.release_inactive_member_directory_assignment();

update public.member_directory
set group_name = null,
    left_at = coalesce(left_at, now())
where is_active = false
  and group_name is not null;

create or replace function public.check_phone_uniqueness()
returns trigger
language plpgsql
as $$
declare
    v_existing_id uuid;
begin
    if NEW.phone is null or NEW.phone = '' then
        return NEW;
    end if;

    select id into v_existing_id
    from public.member_directory
    where church_id = NEW.church_id
      and coalesce(is_active, true) = true
      and phone = NEW.phone
      and id <> coalesce(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and (person_id <> NEW.person_id or person_id is null or NEW.person_id is null)
    limit 1;

    if v_existing_id is not null then
        raise exception 'Phone number % is already in use by another person in this church.', NEW.phone;
    end if;

    return NEW;
end;
$$;
