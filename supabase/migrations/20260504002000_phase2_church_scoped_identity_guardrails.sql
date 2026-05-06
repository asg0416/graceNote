-- Scope legacy person/profile identity sync to a church boundary.
--
-- Before this guardrail, legacy helpers could merge same name+phone across
-- different churches and member_directory.profile_id could point to a profile
-- from another church. That can leak profile-based prayer history across
-- churches in admin detail screens.

set check_function_bodies = off;

create or replace function public.get_or_create_person_id(
  p_full_name text,
  p_phone text,
  p_church_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_person_id uuid;
    v_sanitized_phone text;
begin
    v_sanitized_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');

    if p_full_name is null or v_sanitized_phone = '' then
        return gen_random_uuid();
    end if;

    select person_id into v_person_id
    from public.member_directory
    where church_id = p_church_id
      and full_name = p_full_name
      and regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') = v_sanitized_phone
      and person_id is not null
    order by coalesce(is_active, true) desc, created_at
    limit 1;

    if v_person_id is null then
        select person_id into v_person_id
        from public.profiles
        where church_id = p_church_id
          and full_name = p_full_name
          and regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') = v_sanitized_phone
          and person_id is not null
        order by created_at
        limit 1;
    end if;

    return coalesce(v_person_id, gen_random_uuid());
end;
$$;

create or replace function public.get_or_create_person_id(
  p_full_name text,
  p_phone text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
    -- Without church context, automatic identity reuse is unsafe.
    return gen_random_uuid();
end;
$$;

create or replace function public.handle_member_person_id_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if NEW.person_id is null then
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone, NEW.church_id);
    end if;
    return NEW;
end;
$$;

create or replace function public.handle_profile_person_id_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if NEW.person_id is null then
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone, NEW.church_id);
    end if;
    return NEW;
end;
$$;

create or replace function public.handle_profile_upsert_assign_person_id()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v_person_id uuid;
begin
    if (NEW.full_name is not null and NEW.phone is not null and NEW.phone <> '') then
        select person_id into v_person_id
        from public.member_directory
        where church_id = NEW.church_id
          and full_name = NEW.full_name
          and regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') = regexp_replace(coalesce(NEW.phone, ''), '[^0-9]', '', 'g')
          and person_id is not null
        order by coalesce(is_active, true) desc, created_at
        limit 1;

        if v_person_id is not null then
            NEW.person_id := v_person_id;
            return NEW;
        end if;
    end if;

    if NEW.person_id is not null then
        return NEW;
    end if;

    if (NEW.full_name is not null and NEW.phone is not null and NEW.phone <> '') then
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone, NEW.church_id);
    end if;

    return NEW;
end;
$$;

create or replace function public.ensure_member_directory_profile_same_church()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_profile_church_id uuid;
begin
    if NEW.profile_id is null then
        return NEW;
    end if;

    select church_id into v_profile_church_id
    from public.profiles
    where id = NEW.profile_id;

    if v_profile_church_id is null then
        raise exception 'Linked profile % does not exist.', NEW.profile_id;
    end if;

    if v_profile_church_id <> NEW.church_id then
        raise exception 'Linked profile belongs to another church.';
    end if;

    return NEW;
end;
$$;

drop trigger if exists before_member_directory_profile_same_church on public.member_directory;
create trigger before_member_directory_profile_same_church
before insert or update of profile_id, church_id on public.member_directory
for each row
when (NEW.profile_id is not null)
execute function public.ensure_member_directory_profile_same_church();

create or replace function public.sync_person_data()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if pg_trigger_depth() > 1 then
        return NEW;
    end if;

    update public.member_directory
    set
        full_name = NEW.full_name,
        phone = NEW.phone,
        spouse_name = NEW.spouse_name,
        children_info = NEW.children_info,
        birth_date = NEW.birth_date,
        wedding_anniversary = NEW.wedding_anniversary,
        notes = NEW.notes,
        avatar_url = NEW.avatar_url,
        profile_id = NEW.profile_id,
        is_linked = NEW.is_linked
    where person_id = NEW.person_id
      and church_id = NEW.church_id
      and id <> NEW.id;

    if NEW.profile_id is not null then
        update public.profiles
        set
            full_name = NEW.full_name,
            phone = NEW.phone,
            avatar_url = NEW.avatar_url,
            wedding_anniversary = NEW.wedding_anniversary,
            children_info = NEW.children_info,
            notes = NEW.notes,
            department_id = NEW.department_id
        where person_id = NEW.person_id
          and church_id = NEW.church_id;
    end if;

    return NEW;
end;
$$;

create or replace function public.sync_profile_to_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if pg_trigger_depth() > 1 then
        return NEW;
    end if;

    update public.member_directory
    set
        full_name = NEW.full_name,
        phone = NEW.phone,
        avatar_url = NEW.avatar_url,
        wedding_anniversary = NEW.wedding_anniversary,
        children_info = NEW.children_info,
        notes = NEW.notes
    where person_id = NEW.person_id
      and church_id = NEW.church_id;

    return NEW;
end;
$$;

create or replace function public.sync_profile_to_all_memberships()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if pg_trigger_depth() > 1 then
        return NEW;
    end if;

    if NEW.person_id is not null then
        update public.member_directory
        set profile_id = NEW.id,
            is_linked = true
        where person_id = NEW.person_id
          and church_id = NEW.church_id
          and (profile_id is null or profile_id <> NEW.id);

        update public.group_members
        set profile_id = NEW.id,
            is_active = true
        where member_directory_id in (
            select id
            from public.member_directory
            where person_id = NEW.person_id
              and church_id = NEW.church_id
        )
          and (profile_id is null or profile_id <> NEW.id);
    end if;

    return NEW;
end;
$$;

update public.member_directory md
set profile_id = null,
    is_linked = false
from public.profiles p
where md.profile_id = p.id
  and md.church_id <> p.church_id;
