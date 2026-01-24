-- Migration to fix duplicate phone numbers and enforce uniqueness with security masking
-- 0. Allow NULL phone numbers in member_directory because profiles sync to it
ALTER TABLE public.member_directory ALTER COLUMN phone DROP NOT NULL;

-- 1. Identify and handle existing duplicate phone numbers in profiles
-- We will keep the phone number for the most "valuable" profile and set others to NULL.
-- Priority: 'approved' > 'pending' > 'rejected' > 'none'
-- If same status, keep the most recently created one.

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT phone, id
        FROM (
            SELECT 
                phone, 
                id,
                ROW_NUMBER() OVER (
                    PARTITION BY phone 
                    ORDER BY 
                        CASE admin_status 
                            WHEN 'approved' THEN 1 
                            WHEN 'pending' THEN 2 
                            WHEN 'rejected' THEN 3 
                            ELSE 4 
                        END,
                        created_at DESC
                ) as rank
            FROM public.profiles
            WHERE phone IS NOT NULL AND phone <> ''
        ) t
        WHERE rank > 1
    ) LOOP
        UPDATE public.profiles SET phone = NULL WHERE id = r.id;
    END LOOP;
END $$;

-- 2. Apply the UNIQUE constraint gracefully
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS unique_phone;
ALTER TABLE public.profiles ADD CONSTRAINT unique_phone UNIQUE (phone);

-- 3. Masking function for email (internal use)
CREATE OR REPLACE FUNCTION public.mask_email(p_email TEXT)
RETURNS TEXT AS $$
DECLARE
    parts TEXT[];
    username TEXT;
    domain TEXT;
    username_len INT;
BEGIN
    IF p_email IS NULL OR p_email = '' THEN
        RETURN NULL;
    END IF;
    
    parts := string_to_array(p_email, '@');
    IF array_length(parts, 1) < 2 THEN
        RETURN p_email;
    END IF;
    
    username := parts[1];
    domain := parts[2];
    username_len := length(username);
    
    IF username_len <= 2 THEN
        RETURN username || '***@' || domain;
    ELSE
        RETURN left(username, 1) || '***' || right(username, 1) || '@' || domain;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 4. Create/Update the secure RPC to check for existing phone numbers with MASKING
CREATE OR REPLACE FUNCTION public.check_phone_exists(p_phone TEXT)
RETURNS TABLE (
    p_exists BOOLEAN,
    p_masked_email TEXT,
    p_full_name TEXT
) SECURITY DEFINER 
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        TRUE,
        public.mask_email(email),
        full_name
    FROM public.profiles
    WHERE phone = p_phone
    LIMIT 1;
    
    -- If no rows found, return false
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::TEXT, NULL::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 6. 트리거 로직 강화 (중복 휴대폰 가입 시 Auth 가입 자체를 실패하게 함)
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
DECLARE
  v_role TEXT;
  v_status TEXT;
  v_church_id UUID;
  v_department_id UUID;
  v_raw_church_id TEXT;
  v_raw_dept_id TEXT;
  v_full_name TEXT;
  v_phone TEXT;
BEGIN
  IF (NEW.raw_user_meta_data->>'role_request' = 'admin') OR (NEW.raw_user_meta_data->>'roleRequest' = 'admin') THEN
    v_role := 'admin';
    v_status := 'pending';
  ELSE
    v_role := 'member';
    v_status := 'none';
  END IF;

  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'fullName', '신규 유저');
  v_phone := NEW.raw_user_meta_data->>'phone';

  v_raw_church_id := NULLIF(TRIM(NEW.raw_user_meta_data->>'church_id'), '');
  v_raw_dept_id := NULLIF(TRIM(NEW.raw_user_meta_data->>'department_id'), '');
  
  IF (v_raw_church_id IS NOT NULL AND v_raw_church_id <> 'null') THEN
    IF (v_raw_church_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') THEN
      SELECT id INTO v_church_id FROM public.churches WHERE id = v_raw_church_id::UUID;
    ELSE
      SELECT id INTO v_church_id FROM public.churches WHERE name = v_raw_church_id LIMIT 1;
    END IF;
  END IF;

  IF (v_raw_dept_id IS NOT NULL AND v_raw_dept_id <> 'null' AND v_raw_dept_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') THEN
    v_department_id := v_raw_dept_id::UUID;
  END IF;

  INSERT INTO public.profiles (id, full_name, email, role, admin_status, church_id, department_id, phone, is_onboarding_complete)
  VALUES (NEW.id, v_full_name, NEW.email, v_role, v_status, v_church_id, v_department_id, v_phone, false)
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email = EXCLUDED.email,
    admin_status = EXCLUDED.admin_status,
    church_id = COALESCE(EXCLUDED.church_id, profiles.church_id),
    department_id = COALESCE(EXCLUDED.department_id, profiles.department_id),
    phone = COALESCE(EXCLUDED.phone, profiles.phone);

  RETURN NEW;
EXCEPTION 
  WHEN unique_violation THEN
    -- 이 에러가 발생하면 Supabase Auth 가입 자체가 취소되어 중복 데이터 생성을 막습니다.
    RAISE EXCEPTION '이미 등록된 휴대폰 번호입니다.';
  WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Grant access
GRANT EXECUTE ON FUNCTION public.check_phone_exists(TEXT) TO anon, authenticated;
