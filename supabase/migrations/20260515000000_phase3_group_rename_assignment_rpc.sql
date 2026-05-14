-- Phase 3 group rename compatibility RPC:
-- Renaming a group should only move affiliation labels. It must not rewrite
-- member profile/account links, because older directory rows can contain stale
-- profile_id values that are unrelated to this operation.

set check_function_bodies = off;

create or replace function public.rename_member_directory_group_assignments(
  p_church_id uuid,
  p_department_id uuid,
  p_old_group_name text,
  p_new_group_name text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated_count integer := 0;
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if nullif(btrim(p_old_group_name), '') is null then
    raise exception 'old group name is required.';
  end if;

  if nullif(btrim(p_new_group_name), '') is null then
    raise exception 'new group name is required.';
  end if;

  update public.member_directory
  set group_name = nullif(btrim(p_new_group_name), '')
  where church_id = p_church_id
    and department_id = p_department_id
    and nullif(btrim(group_name), '') = nullif(btrim(p_old_group_name), '');

  get diagnostics v_updated_count = row_count;
  return v_updated_count;
end;
$$;

grant execute on function public.rename_member_directory_group_assignments(
  uuid,
  uuid,
  text,
  text
) to authenticated, service_role;
