-- Limit legacy member_directory -> profiles sync to the explicitly linked
-- profile, and never rewrite profile.phone from regrouping/member_directory
-- edits. Phone is an auth/account identity field and must only change through
-- an explicit verified-phone/account flow, not through group assignment saves.

create or replace function public.sync_person_data()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  update public.member_directory
  set
    full_name = new.full_name,
    phone = new.phone,
    spouse_name = new.spouse_name,
    children_info = new.children_info,
    birth_date = new.birth_date,
    wedding_anniversary = new.wedding_anniversary,
    notes = new.notes,
    avatar_url = new.avatar_url,
    profile_id = new.profile_id,
    is_linked = new.is_linked
  where person_id = new.person_id
    and church_id = new.church_id
    and id <> new.id;

  if new.profile_id is not null then
    update public.profiles p
    set
      full_name = new.full_name,
      avatar_url = new.avatar_url,
      wedding_anniversary = new.wedding_anniversary,
      children_info = new.children_info,
      notes = new.notes,
      department_id = new.department_id
    where p.id = new.profile_id;
  end if;

  return new;
end;
$$;

grant execute on function public.sync_person_data() to authenticated, service_role;
