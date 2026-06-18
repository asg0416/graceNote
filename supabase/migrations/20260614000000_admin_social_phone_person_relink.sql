-- Admin social auth relink:
-- OAuth/email is only a login channel. A verified phone plus matching name in the
-- selected church is the account/person matching signal for admin upgrade.

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
  v_full_name text := btrim(coalesce(p_full_name, ''));
  v_normalized_phone text := public.phase2_normalize_phone(p_phone);
  v_existing_person_id uuid;
  v_existing_phone_profile_id uuid;
  v_existing_login_profile_id uuid;
  v_existing_login_provider text;
  v_candidate_count integer := 0;
  v_conflicting_name text;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if v_full_name = '' then
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

  -- Same phone but different name in the selected church is not safe to auto-link.
  select p.full_name
  into v_conflicting_name
  from public.profiles p
  where p.church_id = $2
    and p.id <> v_user_id
    and public.phase2_normalize_phone(p.phone) = v_normalized_phone
    and btrim(coalesce(p.full_name, '')) <> v_full_name
  limit 1;

  if v_conflicting_name is not null then
    raise exception '인증된 전화번호가 다른 이름의 기존 계정과 연결되어 있습니다. 교회 관리자에게 계정 확인을 요청해 주세요.';
  end if;

  select md.full_name
  into v_conflicting_name
  from public.member_directory md
  where md.church_id = $2
    and public.phase2_normalize_phone(md.phone) = v_normalized_phone
    and btrim(coalesce(md.full_name, '')) <> v_full_name
  limit 1;

  if v_conflicting_name is not null then
    raise exception '인증된 전화번호가 다른 이름의 기존 성도 정보와 연결되어 있습니다. 교회 관리자에게 성도 정보를 확인해 주세요.';
  end if;

  select pe.display_name
  into v_conflicting_name
  from public.people pe
  where pe.church_id = $2
    and pe.normalized_phone = v_normalized_phone
    and btrim(coalesce(pe.display_name, '')) <> v_full_name
  limit 1;

  if v_conflicting_name is not null then
    raise exception '인증된 전화번호가 다른 이름의 기존 성도 정보와 연결되어 있습니다. 교회 관리자에게 성도 정보를 확인해 주세요.';
  end if;

  -- Prefer an exact login-backed profile match over legacy person ambiguity.
  -- Legacy data can contain mismatched person_id rows for the same name/phone;
  -- creating another auth profile would make that split worse.
  select
    p.id,
    case
      when bool_or(i.provider = 'email') then '이메일'
      when bool_or(i.provider = 'kakao') then '카카오'
      when bool_or(i.provider = 'google') then 'Google'
      else '기존 로그인'
    end
  into v_existing_login_profile_id, v_existing_login_provider
  from public.profiles p
  join auth.identities i on i.user_id = p.id
  where p.id <> v_user_id
    and p.church_id = $2
    and public.phase2_normalize_phone(p.phone) = v_normalized_phone
    and btrim(coalesce(p.full_name, '')) = v_full_name
  group by p.id, p.created_at
  order by p.created_at asc nulls last
  limit 1;

  if v_existing_login_profile_id is not null then
    raise exception '이미 % 계정으로 가입되어 있습니다. 기존에 가입한 방식으로 로그인해 주세요.', v_existing_login_provider;
  end if;

  with candidate_people as (
    select p.person_id
    from public.profiles p
    where p.church_id = $2
      and p.id <> v_user_id
      and p.person_id is not null
      and public.phase2_normalize_phone(p.phone) = v_normalized_phone
      and btrim(coalesce(p.full_name, '')) = v_full_name

    union

    select md.person_id
    from public.member_directory md
    where md.church_id = $2
      and md.person_id is not null
      and public.phase2_normalize_phone(md.phone) = v_normalized_phone
      and btrim(coalesce(md.full_name, '')) = v_full_name

    union

    select pe.id
    from public.people pe
    where pe.church_id = $2
      and pe.normalized_phone = v_normalized_phone
      and btrim(coalesce(pe.display_name, '')) = v_full_name
  ),
  distinct_candidates as (
    select distinct person_id
    from candidate_people
    where person_id is not null
  )
  select count(*), (array_agg(person_id order by person_id::text))[1]
  into v_candidate_count, v_existing_person_id
  from distinct_candidates;

  if v_candidate_count > 1 then
    raise exception '동일한 이름과 전화번호의 성도 정보가 여러 개입니다. 교회 관리자에게 성도 정보를 확인해 달라고 요청해 주세요.';
  end if;

  -- If the same verified person already has a login-backed profile, the user
  -- must continue with that account instead of creating another OAuth/email user.
  select
    p.id,
    case
      when bool_or(i.provider = 'email') then '이메일'
      when bool_or(i.provider = 'kakao') then '카카오'
      when bool_or(i.provider = 'google') then 'Google'
      else '기존 로그인'
    end
  into v_existing_login_profile_id, v_existing_login_provider
  from public.profiles p
  join auth.identities i on i.user_id = p.id
  where p.id <> v_user_id
    and (
      (v_existing_person_id is not null and p.person_id = v_existing_person_id)
      or (
        p.church_id = $2
        and public.phase2_normalize_phone(p.phone) = v_normalized_phone
        and btrim(coalesce(p.full_name, '')) = v_full_name
      )
    )
  group by p.id, p.created_at
  order by
    p.created_at asc nulls last
  limit 1;

  if v_existing_login_profile_id is not null then
    raise exception '이미 % 계정으로 가입되어 있습니다. 기존에 가입한 방식으로 로그인해 주세요.', v_existing_login_provider;
  end if;

  select p.id
  into v_existing_phone_profile_id
  from public.profiles p
  where p.id <> v_user_id
    and public.phase2_normalize_phone(p.phone) = v_normalized_phone
    and (
      (v_existing_person_id is not null and p.person_id = v_existing_person_id)
      or (
        p.church_id = $2
        and btrim(coalesce(p.full_name, '')) = v_full_name
      )
    )
  order by case when p.person_id = v_existing_person_id then 0 else 1 end, p.created_at asc nulls last
  limit 1;

  insert into public.profiles (
    id,
    person_id,
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
    v_existing_person_id,
    v_full_name,
    v_email,
    'admin',
    'pending',
    p_church_id,
    p_department_id,
    case when v_existing_phone_profile_id is null then v_normalized_phone else null end,
    false
  )
  on conflict (id) do update set
    person_id = coalesce(v_existing_person_id, public.profiles.person_id),
    full_name = excluded.full_name,
    email = coalesce(excluded.email, public.profiles.email),
    role = 'admin',
    admin_status = 'pending',
    church_id = excluded.church_id,
    department_id = excluded.department_id,
    phone = case
      when v_existing_phone_profile_id is null then excluded.phone
      else public.profiles.phone
    end;

  if v_existing_person_id is not null then
    update public.people
    set
      primary_profile_id = coalesce(primary_profile_id, v_user_id),
      updated_at = now()
    where id = v_existing_person_id;
  end if;
end;
$$;

revoke execute on function public.submit_admin_request(text, uuid, uuid, text) from anon;
grant execute on function public.submit_admin_request(text, uuid, uuid, text) to authenticated;
grant execute on function public.submit_admin_request(text, uuid, uuid, text) to service_role;

create or replace function public.check_admin_existing_login(
  p_full_name text,
  p_church_id uuid,
  p_phone text
) returns table (
  p_exists boolean,
  p_provider text,
  p_message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_full_name text := btrim(coalesce(p_full_name, ''));
  v_normalized_phone text := public.phase2_normalize_phone(p_phone);
  v_existing_person_id uuid;
  v_candidate_count integer := 0;
  v_existing_login_provider text;
begin
  if v_full_name = '' or p_church_id is null or v_normalized_phone is null or length(v_normalized_phone) < 10 then
    return query select false, null::text, null::text;
    return;
  end if;

  if exists (
    select 1
    from public.profiles p
    where (v_user_id is null or p.id <> v_user_id)
      and p.church_id = $2
      and public.phase2_normalize_phone(p.phone) = v_normalized_phone
      and btrim(coalesce(p.full_name, '')) <> v_full_name
  ) or exists (
    select 1
    from public.member_directory md
    where md.church_id = $2
      and public.phase2_normalize_phone(md.phone) = v_normalized_phone
      and btrim(coalesce(md.full_name, '')) <> v_full_name
  ) or exists (
    select 1
    from public.people pe
    where pe.church_id = $2
      and pe.normalized_phone = v_normalized_phone
      and btrim(coalesce(pe.display_name, '')) <> v_full_name
  ) then
    return query select
      true,
      null::text,
      '인증된 전화번호가 다른 이름의 기존 성도 정보와 연결되어 있습니다. 교회 관리자에게 성도 정보를 확인해 주세요.'::text;
    return;
  end if;

  -- Match the app behavior: after phone verification, tell the user to use
  -- the already registered login method before attempting any admin request.
  select
    case
      when count(*) filter (where i.provider = 'email') > 0 then '이메일'
      when count(*) filter (where i.provider = 'kakao') > 0 then '카카오'
      when count(*) filter (where i.provider = 'google') > 0 then 'Google'
      when count(*) > 0 then '기존 로그인'
      else null
    end
  into v_existing_login_provider
  from public.profiles p
  join auth.identities i on i.user_id = p.id
  where (v_user_id is null or p.id <> v_user_id)
    and p.church_id = $2
    and public.phase2_normalize_phone(p.phone) = v_normalized_phone
    and btrim(coalesce(p.full_name, '')) = v_full_name;

  if v_existing_login_provider is not null then
    return query select
      true,
      v_existing_login_provider,
      format('이미 %s 계정으로 가입되어 있습니다. 기존에 가입한 방식으로 로그인해 주세요.', v_existing_login_provider);
    return;
  end if;

  with candidate_people as (
    select p.person_id
    from public.profiles p
    where p.church_id = $2
      and (v_user_id is null or p.id <> v_user_id)
      and p.person_id is not null
      and public.phase2_normalize_phone(p.phone) = v_normalized_phone
      and btrim(coalesce(p.full_name, '')) = v_full_name

    union

    select md.person_id
    from public.member_directory md
    where md.church_id = $2
      and md.person_id is not null
      and public.phase2_normalize_phone(md.phone) = v_normalized_phone
      and btrim(coalesce(md.full_name, '')) = v_full_name

    union

    select pe.id
    from public.people pe
    where pe.church_id = $2
      and pe.normalized_phone = v_normalized_phone
      and btrim(coalesce(pe.display_name, '')) = v_full_name
  ),
  distinct_candidates as (
    select distinct person_id
    from candidate_people
    where person_id is not null
  )
  select count(*), (array_agg(person_id order by person_id::text))[1]
  into v_candidate_count, v_existing_person_id
  from distinct_candidates;

  if v_candidate_count > 1 then
    return query select
      true,
      null::text,
      '동일한 이름과 전화번호의 성도 정보가 여러 개입니다. 교회 관리자에게 성도 정보를 확인해 달라고 요청해 주세요.'::text;
    return;
  end if;

  select
    case
      when count(*) filter (where i.provider = 'email') > 0 then '이메일'
      when count(*) filter (where i.provider = 'kakao') > 0 then '카카오'
      when count(*) filter (where i.provider = 'google') > 0 then 'Google'
      when count(*) > 0 then '기존 로그인'
      else null
    end
  into v_existing_login_provider
  from public.profiles p
  join auth.identities i on i.user_id = p.id
  where (v_user_id is null or p.id <> v_user_id)
    and (
      (v_existing_person_id is not null and p.person_id = v_existing_person_id)
      or (
        p.church_id = $2
        and public.phase2_normalize_phone(p.phone) = v_normalized_phone
        and btrim(coalesce(p.full_name, '')) = v_full_name
      )
    );

  if v_existing_login_provider is not null then
    return query select
      true,
      v_existing_login_provider,
      format('이미 %s 계정으로 가입되어 있습니다. 기존에 가입한 방식으로 로그인해 주세요.', v_existing_login_provider);
    return;
  end if;

  return query select false, null::text, null::text;
end;
$$;

revoke execute on function public.check_admin_existing_login(text, uuid, text) from anon;
grant execute on function public.check_admin_existing_login(text, uuid, text) to authenticated;
grant execute on function public.check_admin_existing_login(text, uuid, text) to service_role;
