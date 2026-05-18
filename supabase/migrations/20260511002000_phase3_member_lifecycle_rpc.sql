-- Phase 3 member lifecycle RPC:
-- Centralize member active/inactive writes while preserving member_directory
-- as a compatibility record during the rollout.

set check_function_bodies = off;

create or replace function public.set_member_directory_active_status(
  p_member_directory_id uuid,
  p_is_active boolean
)
returns public.member_directory
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.member_directory%rowtype;
  v_saved public.member_directory%rowtype;
begin
  if p_member_directory_id is null then
    raise exception 'member_directory_id is required.';
  end if;

  select *
  into v_existing
  from public.member_directory
  where id = p_member_directory_id;

  if not found then
    raise exception 'Member directory row % does not exist.', p_member_directory_id;
  end if;

  update public.member_directory
  set
    is_active = coalesce(p_is_active, true),
    left_at = case
      when coalesce(p_is_active, true) then null
      else coalesce(left_at, now())
    end
  where id = p_member_directory_id
  returning * into v_saved;

  return v_saved;
end;
$$;

grant execute on function public.set_member_directory_active_status(
  uuid,
  boolean
) to authenticated, service_role;
