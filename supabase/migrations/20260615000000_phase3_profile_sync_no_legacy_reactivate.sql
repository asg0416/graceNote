-- Prevent profile relinking from reactivating ended legacy group memberships.
--
-- Re-signup/social auth can attach a new auth profile to an existing person.
-- That link should update profile_id references, but it must not turn historical
-- group_members rows back to active. The active/ended state is now controlled by
-- memberships/regrouping season periods.

create or replace function public.sync_profile_to_all_memberships()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.person_id is not null then
    update public.member_directory
    set profile_id = new.id,
        is_linked = true
    where person_id = new.person_id
      and church_id = new.church_id
      and (profile_id is null or profile_id <> new.id);

    update public.group_members
    set profile_id = new.id
    where member_directory_id in (
        select id
        from public.member_directory
        where person_id = new.person_id
          and church_id = new.church_id
      )
      and (profile_id is null or profile_id <> new.id);
  end if;

  return new;
end;
$function$;

grant execute on function public.sync_profile_to_all_memberships() to authenticated, service_role;
