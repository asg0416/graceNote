-- Align admin social auth with the existing email signup/upgrade policy.
-- OAuth users must get a profile row, then submit the same pending admin request.

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user_profile();

create or replace function public.submit_admin_request(
  p_full_name text,
  p_church_id uuid,
  p_department_id uuid,
  p_phone text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := auth.jwt() ->> 'email';
  v_existing_profile public.profiles%rowtype;
  v_normalized_phone text := public.phase2_normalize_phone(p_phone);
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_full_name is null or btrim(p_full_name) = '' then
    raise exception '관리자 성함을 입력해 주세요.';
  end if;

  if p_church_id is null then
    raise exception '관리할 교회를 선택해 주세요.';
  end if;

  if p_department_id is null then
    raise exception '관리할 부서를 선택해 주세요.';
  end if;

  if v_normalized_phone is null or length(v_normalized_phone) < 10 then
    raise exception '올바른 휴대폰 번호를 입력해 주세요.';
  end if;

  select *
  into v_existing_profile
  from public.profiles
  where phone = v_normalized_phone
    and id <> v_user_id
  limit 1;

  if found then
    raise exception '이미 등록된 전화번호입니다. 기존 앱 계정에서 사용하던 로그인 방식으로 로그인한 뒤 관리자 권한을 신청해 주세요.';
  end if;

  insert into public.profiles (
    id,
    full_name,
    email,
    role,
    admin_status,
    church_id,
    department_id,
    phone,
    is_onboarding_complete
  )
  values (
    v_user_id,
    btrim(p_full_name),
    v_email,
    'admin',
    'pending',
    p_church_id,
    p_department_id,
    v_normalized_phone,
    false
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    email = coalesce(excluded.email, public.profiles.email),
    role = 'admin',
    admin_status = 'pending',
    church_id = excluded.church_id,
    department_id = excluded.department_id,
    phone = excluded.phone;
end;
$$;

grant execute on function public.submit_admin_request(text, uuid, uuid, text) to anon;
grant execute on function public.submit_admin_request(text, uuid, uuid, text) to authenticated;
grant execute on function public.submit_admin_request(text, uuid, uuid, text) to service_role;
