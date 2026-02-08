


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."check_group_leader_permission"("target_church_id" "uuid", "target_department_id" "uuid", "target_group_name" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- A. Check if user is a Church Admin (Global Admin)
  -- Reusing existing helper if available, or manual check for safety
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND (
      (role = 'admin' AND admin_status = 'approved' AND church_id = target_church_id)
      OR is_master = true
    )
  ) THEN
    RETURN TRUE;
  END IF;

  -- B. Check if user is a Leader/Board of the specific group
  RETURN EXISTS (
    SELECT 1
    FROM public.group_members gm
    JOIN public.groups g ON gm.group_id = g.id
    WHERE gm.profile_id = auth.uid()
      AND gm.role_in_group IN ('leader', 'admin') -- Check role in group
      AND gm.is_active = true
      AND g.church_id = target_church_id
      AND g.department_id = target_department_id
      AND g.name = target_group_name -- String match on Group Name
  );
END;
$$;


ALTER FUNCTION "public"."check_group_leader_permission"("target_church_id" "uuid", "target_department_id" "uuid", "target_group_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_is_master"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND is_master = true
  );
END;
$$;


ALTER FUNCTION "public"."check_is_master"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_phone_exists"("p_phone" "text", "p_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("p_exists" boolean, "p_masked_email" "text", "p_full_name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        TRUE,
        public.mask_email(email),
        full_name
    FROM public.profiles
    WHERE phone = p_phone
      AND (p_user_id IS NULL OR id <> p_user_id)
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::TEXT, NULL::TEXT;
    END IF;
END;
$$;


ALTER FUNCTION "public"."check_phone_exists"("p_phone" "text", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_phone_uniqueness"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_existing_id UUID;
BEGIN
    IF NEW.phone IS NULL OR NEW.phone = '' THEN
        RETURN NEW;
    END IF;

    SELECT id INTO v_existing_id
    FROM public.member_directory
    WHERE phone = NEW.phone
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND (person_id <> NEW.person_id OR person_id IS NULL OR NEW.person_id IS NULL)
      AND NOT (church_id = NEW.church_id AND department_id = NEW.department_id)
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        RAISE EXCEPTION 'Phone number % is already in use by another person.', NEW.phone;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_phone_uniqueness"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_orphaned_users"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'auth', 'public'
    AS $$
DECLARE
  deleted_count INT;
BEGIN
  WITH targets AS (
    SELECT id FROM public.profiles 
    WHERE is_onboarding_complete = false 
    AND created_at < (NOW() - INTERVAL '24 hours')
    AND is_master = false
  )
  DELETE FROM auth.users 
  WHERE id IN (SELECT id FROM targets);
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;


ALTER FUNCTION "public"."cleanup_orphaned_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_together_count"("row_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.prayer_entries
  SET together_count = GREATEST(COALESCE(together_count, 0) - 1, 0)
  WHERE id = row_id;
END;
$$;


ALTER FUNCTION "public"."decrement_together_count"("row_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_self_in_onboarding"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'auth', 'public'
    AS $$
BEGIN
  -- 프로필이 없거나 (트리거 실패), 프로필은 있으되 온보딩이 미완료인 경우만 삭제 허용
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()) OR EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND is_onboarding_complete = false
  ) THEN
    DELETE FROM auth.users WHERE id = auth.uid();
  ELSE
    RAISE EXCEPTION '완료된 계정은 자가 삭제할 수 없습니다.';
  END IF;
END;
$$;


ALTER FUNCTION "public"."delete_self_in_onboarding"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_week_exists"("p_church_id" "uuid", "p_week_date" "date") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_week_id UUID;
BEGIN
  -- 1. Check if exists
  SELECT id INTO v_week_id FROM public.weeks 
  WHERE church_id = p_church_id AND week_date = p_week_date;

  IF v_week_id IS NOT NULL THEN
    RETURN v_week_id;
  END IF;

  -- 2. Insert if not exists (Security Definer allows this even if user lacks INSERT permission)
  INSERT INTO public.weeks (church_id, week_date)
  VALUES (p_church_id, p_week_date)
  ON CONFLICT (church_id, week_date) DO NOTHING;

  -- 3. Return the ID (newly created or existing)
  SELECT id INTO v_week_id FROM public.weeks 
  WHERE church_id = p_church_id AND week_date = p_week_date;

  RETURN v_week_id;
END;
$$;


ALTER FUNCTION "public"."ensure_week_exists"("p_church_id" "uuid", "p_week_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_church_member_counts"() RETURNS TABLE("church_id" "uuid", "member_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT p.church_id, COUNT(*)::INT as member_count
  FROM public.profiles p
  WHERE p.church_id IS NOT NULL
  GROUP BY p.church_id;
END;
$$;


ALTER FUNCTION "public"."get_church_member_counts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_church_id"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN (SELECT church_id FROM public.profiles WHERE id = auth.uid());
END;
$$;


ALTER FUNCTION "public"."get_my_church_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_matched_church_id"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_phone text;
  v_church_id uuid;
BEGIN
  -- Get the verified phone from the profile
  SELECT phone INTO v_phone FROM public.profiles WHERE id = auth.uid();
  
  IF v_phone IS NULL THEN
    RETURN NULL;
  END IF;

  -- Find the church_id from member_directory
  SELECT church_id INTO v_church_id 
  FROM public.member_directory 
  WHERE phone = v_phone 
  LIMIT 1;

  RETURN v_church_id;
END;
$$;


ALTER FUNCTION "public"."get_my_matched_church_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_profile"() RETURNS TABLE("id" "uuid", "full_name" "text", "role" "text", "admin_status" "text", "is_master" boolean, "church_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN QUERY SELECT p.id, p.full_name, p.role, p.admin_status, p.is_master, p.church_id 
  FROM public.profiles p WHERE p.id = auth.uid();
END;
$$;


ALTER FUNCTION "public"."get_my_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_person_id"("p_full_name" "text", "p_phone" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_person_id UUID;
    v_sanitized_phone TEXT;
BEGIN
    -- 전화번호에서 숫자만 추출
    v_sanitized_phone := regexp_replace(p_phone, '[^0-9]', '', 'g');

    -- member_directory에서 동일한 이름과 정제된 전화번호로 person_id 탐색
    SELECT person_id INTO v_person_id 
    FROM public.member_directory 
    WHERE full_name = p_full_name 
      AND regexp_replace(phone, '[^0-9]', '', 'g') = v_sanitized_phone 
      AND person_id IS NOT NULL
    LIMIT 1;

    IF v_person_id IS NULL THEN
        -- profiles에서 동일한 이름과 정제된 전화번호로 person_id 탐색
        SELECT person_id INTO v_person_id 
        FROM public.profiles 
        WHERE full_name = p_full_name 
          AND regexp_replace(phone, '[^0-9]', '', 'g') = v_sanitized_phone 
          AND person_id IS NOT NULL
        LIMIT 1;
    END IF;

    -- 찾지 못한 경우 새로운 UUID 생성
    IF v_person_id IS NULL THEN
        v_person_id := gen_random_uuid();
    END IF;

    RETURN v_person_id;
END;
$$;


ALTER FUNCTION "public"."get_or_create_person_id"("p_full_name" "text", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_inquiry_response_flags"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- 답변을 단 사람이 관리자인 경우
  IF NEW.admin_id IS NOT NULL THEN
    UPDATE public.inquiries
    SET 
      updated_at = NOW(),
      last_responder_role = 'admin',
      is_admin_unread = FALSE, -- 관리자가 방금 답을 달았으니 읽은 것임
      is_user_unread = TRUE,   -- 유저에게 새 소식이 생김
      status = CASE WHEN status = 'pending' THEN 'in_progress' ELSE status END
    WHERE id = NEW.inquiry_id;
  ELSE
    -- 유저가 추가 답변을 단 경우
    UPDATE public.inquiries
    SET 
      updated_at = NOW(),
      last_responder_role = 'user',
      is_admin_unread = TRUE,  -- 관리자에게 새 소식이 생김
      is_user_unread = FALSE   -- 유저가 방금 글을 썼으니 읽은 것임
    WHERE id = NEW.inquiry_id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_inquiry_response_flags"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_inquiry_response_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- If the responder is an admin
  IF NEW.admin_id IS NOT NULL THEN
    UPDATE public.inquiries
    SET 
      updated_at = NOW(),
      last_responder_role = 'admin',
      is_admin_unread = FALSE, -- Clear admin unread flag
      is_user_unread = TRUE,   -- Set user unread flag for app
      status = CASE WHEN status = 'pending' THEN 'in_progress' ELSE status END
    WHERE id = NEW.inquiry_id;
  ELSE
    -- If the responder is a user (student/member)
    UPDATE public.inquiries
    SET 
      updated_at = NOW(),
      last_responder_role = 'user',
      is_admin_unread = TRUE,  -- Set admin unread flag
      is_user_unread = FALSE   -- Clear user unread flag
    WHERE id = NEW.inquiry_id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_inquiry_response_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_member_directory_unlinking"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- profile_id가 NULL로 변하면 is_linked도 false로 변경
  IF NEW.profile_id IS NULL THEN
    NEW.is_linked := false;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_member_directory_unlinking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_member_person_id_assignment"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF NEW.person_id IS NULL THEN
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_member_person_id_assignment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_role TEXT;
  v_status TEXT;
  v_church_id UUID;
  v_department_id UUID;
  v_raw_church_id TEXT;
  v_raw_dept_id TEXT;
BEGIN
  IF (NEW.raw_user_meta_data->>'role_request' = 'admin') OR (NEW.raw_user_meta_data->>'roleRequest' = 'admin') THEN
    v_role := 'admin';
    v_status := 'pending';
  ELSE
    v_role := 'member';
    v_status := 'none';
  END IF;

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

  INSERT INTO public.profiles (
    id, full_name, email, role, admin_status, church_id, department_id, phone, is_onboarding_complete
  )
  VALUES (
    NEW.id, 
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'fullName', '신규 유저'), 
    NEW.email, v_role, v_status, v_church_id, v_department_id, NEW.raw_user_meta_data->>'phone', false
  )
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
    RAISE EXCEPTION '이미 등록된 휴대폰 번호입니다.';
  WHEN OTHERS THEN
    -- 오류 로그 로그 기록 후에도 유저는 생성되도록 RETURN NEW (단, 에러는 debug_logs에 기록)
    INSERT INTO public.debug_logs (level, message, payload)
    VALUES ('ERROR', 'Profile Trigger Failed: ' || SQLERRM, jsonb_build_object('user_id', NEW.id));
    RETURN NEW;
END;
$_$;


ALTER FUNCTION "public"."handle_new_user_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_prayer_interaction_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF (NEW.interaction_type = 'pray') THEN
            UPDATE public.prayer_entries
            SET together_count = COALESCE(together_count, 0) + 1
            WHERE id = NEW.prayer_id;
        END IF;
    ELSIF (TG_OP = 'DELETE') THEN
        IF (OLD.interaction_type = 'pray') THEN
            UPDATE public.prayer_entries
            SET together_count = GREATEST(COALESCE(together_count, 0) - 1, 0)
            WHERE id = OLD.prayer_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."handle_prayer_interaction_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_profile_person_id_assignment"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF NEW.person_id IS NULL THEN
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_profile_person_id_assignment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_profile_upsert_assign_person_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_person_id UUID;
BEGIN
    -- [IMPROVED] 이름과 번호가 유효할 때만 명부와 동기화 시도
    IF (NEW.full_name IS NOT NULL AND NEW.phone IS NOT NULL AND NEW.phone != '') THEN
        -- 명부에서 매칭되는 인물 ID 탐색 (번호 정제 필수)
        SELECT person_id INTO v_person_id
        FROM public.member_directory
        WHERE full_name = NEW.full_name 
          AND regexp_replace(phone, '[^0-9]', '', 'g') = regexp_replace(NEW.phone, '[^0-9]', '', 'g')
          AND person_id IS NOT NULL
        LIMIT 1;

        -- 매칭되는 명부 데이터가 있다면 강제 할당 (잘못 생성된 person_id 덮어쓰기 포함)
        IF v_person_id IS NOT NULL THEN
            NEW.person_id := v_person_id;
            RETURN NEW;
        END IF;
    END IF;

    -- 매칭에 실패했고 기존 ID가 있다면 유지
    IF NEW.person_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- 정말 아무것도 없을 때만 새로 생성
    IF (NEW.full_name IS NOT NULL AND NEW.phone IS NOT NULL AND NEW.phone != '') THEN
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_profile_upsert_assign_person_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_together_count"("row_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.prayer_entries
  SET together_count = COALESCE(together_count, 0) + 1
  WHERE id = row_id;
END;
$$;


ALTER FUNCTION "public"."increment_together_count"("row_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin_approved"("target_church_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() 
    AND (
      (role = 'admin' AND admin_status = 'approved' AND (target_church_id IS NULL OR church_id = target_church_id))
      OR (is_master = true)
    )
  );
END;
$$;


ALTER FUNCTION "public"."is_admin_approved"("target_church_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_in_church"("target_church_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND (church_id = target_church_id OR is_master = true)
  );
END;
$$;


ALTER FUNCTION "public"."is_in_church"("target_church_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_leader"("target_church_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.group_members gm
    JOIN public.groups g ON gm.group_id = g.id
    WHERE gm.profile_id = auth.uid()
    AND gm.role_in_group IN ('leader', 'admin')
    AND gm.is_active = true
    AND (target_church_id IS NULL OR g.church_id = target_church_id)
  );
END;
$$;


ALTER FUNCTION "public"."is_leader"("target_church_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."manage_inquiry_unread_flags"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- 신규 문의 작성 시 (유저가 작성)
  IF TG_OP = 'INSERT' THEN
    NEW.is_admin_unread := TRUE;
    NEW.is_user_unread := FALSE;
    NEW.last_responder_role := 'user';
    
    -- church_id가 없는 경우 작성자의 프로필에서 가져옴
    IF NEW.church_id IS NULL THEN
      SELECT church_id INTO NEW.church_id FROM public.profiles WHERE id = NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."manage_inquiry_unread_flags"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mask_email"("p_email" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
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
$$;


ALTER FUNCTION "public"."mask_email"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."regroup_members"("p_member_ids" "uuid"[], "p_target_group_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_group_name TEXT;
    v_dept_id UUID;
    v_church_id UUID;
BEGIN
    -- 1. Get group info if target_group_id is provided
    IF p_target_group_id IS NOT NULL THEN
        SELECT name, department_id, church_id INTO v_group_name, v_dept_id, v_church_id
        FROM public.groups
        WHERE id = p_target_group_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Group not found';
        END IF;
    ELSE
        -- If moving to unassigned, we assume the department and church stay the same as current
        v_group_name := NULL;

        -- Get department_id from the first member
        IF array_length(p_member_ids, 1) > 0 THEN
            SELECT department_id INTO v_dept_id FROM public.member_directory WHERE id = p_member_ids[1] LIMIT 1;
        END IF;
    END IF;

    -- 2. Update member_directory
    UPDATE public.member_directory
    SET group_name = v_group_name
    WHERE id = ANY(p_member_ids);

    -- 3. Synchronize group_members (for users who have a profile linked)
    IF p_target_group_id IS NOT NULL THEN
        -- Insert or update group membership
        -- [FIX] role_in_group 필드 추가 및 데이터 동기화
        INSERT INTO public.group_members (profile_id, group_id, member_directory_id, role_in_group, is_active)
        SELECT profile_id, p_target_group_id, id, role_in_group, true
        FROM public.member_directory
        WHERE id = ANY(p_member_ids) AND profile_id IS NOT NULL
        ON CONFLICT (group_id, member_directory_id) DO UPDATE SET
            is_active = true,
            profile_id = EXCLUDED.profile_id,
            role_in_group = EXCLUDED.role_in_group; -- 역할도 동기화!

        -- Deactivate other memberships in the SAME department for these profiles
        -- [REFINEMENT] 같은 member_directory_id에 대해서만 비활성화하도록 수정 (다른 디렉토리 기반 소속은 유지)
        UPDATE public.group_members gm
        SET is_active = false
        WHERE gm.member_directory_id = ANY(p_member_ids)
        AND gm.group_id <> p_target_group_id;

    ELSIF v_dept_id IS NOT NULL THEN
        -- If moving to unassigned, deactivate memberships in the current department
        -- [REFINEMENT] 같은 member_directory_id에 대해서만 비활성화
        UPDATE public.group_members gm
        SET is_active = false
        WHERE gm.member_directory_id = ANY(p_member_ids);
    END IF;

END;
$$;


ALTER FUNCTION "public"."regroup_members"("p_member_ids" "uuid"[], "p_target_group_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_admin_request"("p_full_name" "text", "p_church_id" "uuid", "p_department_id" "uuid", "p_phone" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Update the user's profile and sync email from auth.jwt()
  UPDATE public.profiles
  SET 
    full_name = p_full_name,
    church_id = p_church_id,
    department_id = p_department_id,
    phone = p_phone,
    role = 'admin',      -- Set role to admin so they are treated as an admin candidate
    admin_status = 'pending', -- Mark as pending approval
    email = auth.jwt() ->> 'email' -- Sync email from session
  WHERE id = auth.uid();
END;
$$;


ALTER FUNCTION "public"."submit_admin_request"("p_full_name" "text", "p_church_id" "uuid", "p_department_id" "uuid", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_directory_to_group_members"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_new_group_id UUID;
BEGIN
  -- 1. If profile_id is NULL, no need to sync to group_members (not a real user yet)
  IF NEW.profile_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 2. Check if group_name changed
  IF OLD.group_name IS DISTINCT FROM NEW.group_name OR NEW.profile_id IS DISTINCT FROM OLD.profile_id THEN
    
    -- Find the Group ID corresponding to the new group name (in the same church/dept)
    SELECT id INTO v_new_group_id
    FROM public.groups
    WHERE church_id = NEW.church_id
      AND department_id = NEW.department_id
      AND name = NEW.group_name
    LIMIT 1;

    IF v_new_group_id IS NOT NULL THEN
      -- A. Deactivate old membership
      UPDATE public.group_members
      SET is_active = false
      WHERE profile_id = NEW.profile_id 
        AND is_active = true;

      -- B. Insert or Reactivate new membership
      --    Check if record already exists (even if inactive) to prevent duplicates
      IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id = v_new_group_id AND profile_id = NEW.profile_id) THEN
          UPDATE public.group_members
          SET is_active = true,
              role_in_group = COALESCE(role_in_group, 'member'), -- Keep existing role if set, else member
              joined_at = NOW() -- Update join time to now
          WHERE group_id = v_new_group_id AND profile_id = NEW.profile_id;
      ELSE
          INSERT INTO public.group_members (group_id, profile_id, role_in_group, is_active, joined_at)
          VALUES (
            v_new_group_id, 
            NEW.profile_id, 
            'member', 
            true, 
            NOW()
          );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_directory_to_group_members"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_inquiry_church_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.church_id IS NULL THEN
    SELECT church_id INTO NEW.church_id FROM public.profiles WHERE id = NEW.user_id;
  END IF;
  -- 초기 생성 시엔 유저가 쓴 것이므로
  NEW.last_responder_role := 'user';
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_inquiry_church_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_member_linkage_to_others"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    IF NEW.profile_id IS NOT NULL AND NEW.person_id IS NOT NULL THEN
        -- 같은 person_id를 가진 다른 명부에도 똑같은 profile_id 전파
        UPDATE public.member_directory
        SET 
            profile_id = NEW.profile_id,
            is_linked = true
        WHERE person_id = NEW.person_id 
          AND (profile_id IS NULL OR profile_id != NEW.profile_id);
          
        -- 해당 인물의 모든 그룹 멤버십에도 profile_id 전파
        UPDATE public.group_members
        SET profile_id = NEW.profile_id
        WHERE member_directory_id IN (
            SELECT id FROM public.member_directory WHERE person_id = NEW.person_id
        ) AND (profile_id IS NULL OR profile_id != NEW.profile_id);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_member_linkage_to_others"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_person_data"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Prevent infinite loop
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- Sync to other records in member_directory
    UPDATE public.member_directory
    SET 
        full_name = NEW.full_name,
        phone = NEW.phone,
        spouse_name = NEW.spouse_name,
        children_info = NEW.children_info,
        birth_date = NEW.birth_date,
        wedding_anniversary = NEW.wedding_anniversary,
        notes = NEW.notes,
        avatar_url = NEW.avatar_url,
        profile_id = NEW.profile_id,
        is_linked = NEW.is_linked,
        church_id = NEW.church_id,
        department_id = NEW.department_id
    WHERE person_id = NEW.person_id AND id <> NEW.id;

    -- Sync to profiles (ONLY IF LINKED)
    -- [FIX] Do not update profiles if we are unlinked (profile_id is NULL)
    -- This prevents circular update errors during Profile Deletion (Cascade Set Null)
    IF NEW.profile_id IS NOT NULL THEN
        UPDATE public.profiles
        SET 
            full_name = NEW.full_name,
            phone = NEW.phone,
            avatar_url = NEW.avatar_url,
            wedding_anniversary = NEW.wedding_anniversary,
            children_info = NEW.children_info,
            notes = NEW.notes,
            church_id = NEW.church_id,
            department_id = NEW.department_id
        WHERE person_id = NEW.person_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_person_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_profile_and_directory_by_phone"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_directory_record RECORD;
BEGIN
    -- Prevent infinite loop
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- If phone is provided, find a matching record in member_directory that isn't linked yet
    IF NEW.phone IS NOT NULL AND NEW.phone <> '' THEN
        SELECT id, church_id, department_id, person_id INTO v_directory_record
        FROM public.member_directory
        WHERE phone = NEW.phone
        ORDER BY created_at DESC
        LIMIT 1;

        IF v_directory_record.id IS NOT NULL THEN
            -- Update NEW profile record with directory metadata before it's saved (if it's a BEFORE trigger)
            -- But since this might be AFTER, we do an UPDATE
            UPDATE public.profiles
            SET 
                person_id = COALESCE(person_id, v_directory_record.person_id),
                church_id = COALESCE(church_id, v_directory_record.church_id),
                department_id = COALESCE(department_id, v_directory_record.department_id)
            WHERE id = NEW.id;

            -- Update member_directory to link to this profile
            UPDATE public.member_directory
            SET 
                profile_id = NEW.id,
                is_linked = true,
                person_id = COALESCE(person_id, NEW.person_id)
            WHERE id = v_directory_record.id;

            -- Also ensure group_members are updated with the correct profile_id
            UPDATE public.group_members
            SET profile_id = NEW.id
            WHERE member_directory_id = v_directory_record.id
               OR (profile_id IS NULL AND member_directory_id IS NULL AND group_id IN (
                   SELECT id FROM groups WHERE church_id = v_directory_record.church_id
               ));
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_profile_and_directory_by_phone"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_profile_id_by_phone"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- [FIX] Do not attempt to re-link if we are intentionally unlinking (or cascade deleting)
    -- Only search if:
    -- 1. It's a new record (INSERT)
    -- 2. It was previously unlinked (OLD.profile_id IS NULL)
    -- 3. The phone number has changed (NEW.phone <> OLD.phone)
    IF NEW.profile_id IS NULL AND NEW.phone IS NOT NULL AND NEW.phone <> '' THEN
        IF (TG_OP = 'INSERT') OR 
           (TG_OP = 'UPDATE' AND OLD.profile_id IS NULL) OR 
           (TG_OP = 'UPDATE' AND NEW.phone IS DISTINCT FROM OLD.phone) THEN
           
            SELECT profile_id INTO NEW.profile_id
            FROM public.member_directory
            WHERE phone = NEW.phone
              AND profile_id IS NOT NULL
            LIMIT 1;
            
            IF NEW.profile_id IS NULL THEN
                SELECT id INTO NEW.profile_id
                FROM public.profiles
                WHERE phone = NEW.phone
                LIMIT 1;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_profile_id_by_phone"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_profile_id_to_group_members"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- person_id가 새로 설정되거나 변경된 경우
    IF (TG_OP = 'INSERT' AND NEW.person_id IS NOT NULL) OR 
       (TG_OP = 'UPDATE' AND NEW.person_id IS DISTINCT FROM OLD.person_id AND NEW.person_id IS NOT NULL) THEN
        
        -- 해당 명부(member_directory)와 연결된 모든 group_members 레코드에 profile_id 전파
        UPDATE public.group_members
        SET profile_id = NEW.id
        WHERE member_directory_id = NEW.person_id
          AND (profile_id IS NULL OR profile_id <> NEW.id);
          
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_profile_id_to_group_members"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_profile_to_all_memberships"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;
    IF NEW.person_id IS NOT NULL THEN
        -- 명부 업데이트
        UPDATE public.member_directory SET profile_id = NEW.id, is_linked = true
        WHERE person_id = NEW.person_id AND (profile_id IS NULL OR profile_id != NEW.id);
        
        -- 소속 업데이트
        UPDATE public.group_members SET profile_id = NEW.id, is_active = true
        WHERE member_directory_id IN (SELECT id FROM public.member_directory WHERE person_id = NEW.person_id)
          AND (profile_id IS NULL OR profile_id != NEW.id);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_profile_to_all_memberships"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_profile_to_member"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Prevent infinite loop
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- Sync to all matching member_directory records (Fields EXIST in member_directory)
    UPDATE public.member_directory
    SET 
        full_name = NEW.full_name,
        phone = NEW.phone,
        avatar_url = NEW.avatar_url,
        wedding_anniversary = NEW.wedding_anniversary,
        children_info = NEW.children_info,
        notes = NEW.notes
        -- birth_date missing in profiles NEW record
    WHERE person_id = NEW.person_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_profile_to_member"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."attendance" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "week_id" "uuid",
    "group_member_id" "uuid",
    "status" "text" DEFAULT 'absent'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "directory_member_id" "uuid",
    "group_id" "uuid",
    CONSTRAINT "attendance_status_check" CHECK (("status" = ANY (ARRAY['present'::"text", 'absent'::"text", 'late'::"text", 'excused'::"text"])))
);


ALTER TABLE "public"."attendance" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."churches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."churches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."debug_logs" (
    "id" integer NOT NULL,
    "level" "text",
    "message" "text",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."debug_logs" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."debug_logs_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."debug_logs_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."debug_logs_id_seq" OWNED BY "public"."debug_logs"."id";



CREATE TABLE IF NOT EXISTS "public"."departments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "church_id" "uuid",
    "name" "text" NOT NULL,
    "profile_mode" "text" DEFAULT 'individual'::"text",
    "allow_late_entry" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "color_hex" "text",
    CONSTRAINT "departments_profile_mode_check" CHECK (("profile_mode" = ANY (ARRAY['individual'::"text", 'couple'::"text"])))
);


ALTER TABLE "public"."departments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."families" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "church_id" "uuid",
    "department_id" "uuid",
    "name" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."families" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_id" "uuid",
    "profile_id" "uuid",
    "role_in_group" "text" DEFAULT 'member'::"text",
    "is_active" boolean DEFAULT true,
    "joined_at" timestamp with time zone DEFAULT "now"(),
    "member_directory_id" "uuid",
    CONSTRAINT "group_members_role_in_group_check" CHECK (("role_in_group" = ANY (ARRAY['leader'::"text", 'member'::"text"])))
);

ALTER TABLE ONLY "public"."group_members" REPLICA IDENTITY FULL;


ALTER TABLE "public"."group_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."groups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "church_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "department_id" "uuid",
    "color_hex" "text",
    "is_active" boolean DEFAULT true
);


ALTER TABLE "public"."groups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inquiries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "title" "text" NOT NULL,
    "content" "text" NOT NULL,
    "category" "text" DEFAULT 'bug'::"text",
    "status" "text" DEFAULT 'pending'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_last_read_at" timestamp with time zone DEFAULT "now"(),
    "admin_last_read_at" timestamp with time zone DEFAULT "now"(),
    "last_responder_role" "text" DEFAULT 'user'::"text",
    "church_id" "uuid",
    "is_admin_unread" boolean DEFAULT true,
    "is_user_unread" boolean DEFAULT false,
    "images" "text"[] DEFAULT ARRAY[]::"text"[],
    CONSTRAINT "inquiries_last_responder_role_check" CHECK (("last_responder_role" = ANY (ARRAY['user'::"text", 'admin'::"text"]))),
    CONSTRAINT "inquiries_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'completed'::"text"])))
);

ALTER TABLE ONLY "public"."inquiries" REPLICA IDENTITY FULL;


ALTER TABLE "public"."inquiries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inquiry_responses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inquiry_id" "uuid",
    "admin_id" "uuid",
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "images" "text"[] DEFAULT ARRAY[]::"text"[]
);

ALTER TABLE ONLY "public"."inquiry_responses" REPLICA IDENTITY FULL;


ALTER TABLE "public"."inquiry_responses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."member_directory" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "church_id" "uuid",
    "department_id" "uuid",
    "full_name" "text" NOT NULL,
    "phone" "text",
    "group_name" "text",
    "role_in_group" "text" DEFAULT 'member'::"text",
    "family_name" "text",
    "spouse_name" "text",
    "children_info" "text",
    "is_linked" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "notes" "text",
    "profile_id" "uuid",
    "birth_date" "date",
    "wedding_anniversary" "date",
    "is_active" boolean DEFAULT true,
    "avatar_url" "text",
    "joined_at" timestamp with time zone DEFAULT "now"(),
    "left_at" timestamp with time zone,
    "person_id" "uuid"
);

ALTER TABLE ONLY "public"."member_directory" REPLICA IDENTITY FULL;


ALTER TABLE "public"."member_directory" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."newsletters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "week_id" "uuid",
    "church_id" "uuid",
    "content" "text",
    "sent_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."newsletters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notice_reads" (
    "notice_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "read_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."notice_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "church_id" "uuid",
    "department_id" "uuid",
    "title" "text" NOT NULL,
    "content" "text" NOT NULL,
    "category" "text" DEFAULT 'general'::"text",
    "is_global" boolean DEFAULT false,
    "target_role" "text" DEFAULT 'all'::"text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "is_pinned" boolean DEFAULT false
);


ALTER TABLE "public"."notices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."phone_verifications" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "phone" "text" NOT NULL,
    "code" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "is_verified" boolean DEFAULT false
);


ALTER TABLE "public"."phone_verifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prayer_ai_backups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "prayer_entry_id" "uuid",
    "original_content" "text" NOT NULL,
    "refined_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."prayer_ai_backups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prayer_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "week_id" "uuid",
    "group_id" "uuid",
    "author_id" "uuid",
    "member_id" "uuid",
    "content" "text",
    "ai_refined_content" "text",
    "status" "text" DEFAULT 'draft'::"text",
    "is_refining" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "directory_member_id" "uuid",
    "together_count" integer DEFAULT 0,
    CONSTRAINT "prayer_entries_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'published'::"text"])))
);


ALTER TABLE "public"."prayer_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prayer_interactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "prayer_id" "uuid",
    "profile_id" "uuid",
    "interaction_type" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "prayer_interactions_interaction_type_check" CHECK (("interaction_type" = ANY (ARRAY['pray'::"text", 'save'::"text"])))
);


ALTER TABLE "public"."prayer_interactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "church_id" "uuid",
    "full_name" "text" NOT NULL,
    "role" "text" DEFAULT 'member'::"text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "department_id" "uuid",
    "family_id" "uuid",
    "spouse_id" "uuid",
    "admin_status" "text" DEFAULT 'none'::"text",
    "is_master" boolean DEFAULT false,
    "is_onboarding_complete" boolean DEFAULT false,
    "phone" "text",
    "wedding_anniversary" "date",
    "children_info" "text",
    "notes" "text",
    "last_notice_checked_at" timestamp with time zone DEFAULT "now"(),
    "email" "text",
    "person_id" "uuid"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_church_list" AS
 SELECT "id",
    "name"
   FROM "public"."churches";


ALTER VIEW "public"."public_church_list" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_department_list" AS
 SELECT "id",
    "church_id",
    "name"
   FROM "public"."departments";


ALTER VIEW "public"."public_department_list" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."weeks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "church_id" "uuid",
    "week_date" "date" NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."weeks" OWNER TO "postgres";


ALTER TABLE ONLY "public"."debug_logs" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."debug_logs_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."attendance"
    ADD CONSTRAINT "attendance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance"
    ADD CONSTRAINT "attendance_week_id_directory_member_id_key" UNIQUE ("week_id", "directory_member_id");



ALTER TABLE ONLY "public"."churches"
    ADD CONSTRAINT "churches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."debug_logs"
    ADD CONSTRAINT "debug_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."families"
    ADD CONSTRAINT "families_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_group_id_member_directory_id_key" UNIQUE ("group_id", "member_directory_id");



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_church_id_department_id_name_key" UNIQUE ("church_id", "department_id", "name");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inquiries"
    ADD CONSTRAINT "inquiries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inquiry_responses"
    ADD CONSTRAINT "inquiry_responses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."member_directory"
    ADD CONSTRAINT "member_directory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."member_directory"
    ADD CONSTRAINT "member_directory_unique_assignment" UNIQUE ("church_id", "department_id", "group_name", "full_name", "phone");



ALTER TABLE ONLY "public"."newsletters"
    ADD CONSTRAINT "newsletters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notice_reads"
    ADD CONSTRAINT "notice_reads_pkey" PRIMARY KEY ("notice_id", "user_id");



ALTER TABLE ONLY "public"."notices"
    ADD CONSTRAINT "notices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."phone_verifications"
    ADD CONSTRAINT "phone_verifications_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "public"."phone_verifications"
    ADD CONSTRAINT "phone_verifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prayer_ai_backups"
    ADD CONSTRAINT "prayer_ai_backups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prayer_entries"
    ADD CONSTRAINT "prayer_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prayer_entries"
    ADD CONSTRAINT "prayer_entries_week_id_directory_member_id_key" UNIQUE ("week_id", "directory_member_id");



ALTER TABLE ONLY "public"."prayer_interactions"
    ADD CONSTRAINT "prayer_interactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prayer_interactions"
    ADD CONSTRAINT "prayer_interactions_prayer_id_profile_id_interaction_type_key" UNIQUE ("prayer_id", "profile_id", "interaction_type");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "unique_phone" UNIQUE ("phone");



ALTER TABLE ONLY "public"."weeks"
    ADD CONSTRAINT "weeks_church_id_week_date_key" UNIQUE ("church_id", "week_date");



ALTER TABLE ONLY "public"."weeks"
    ADD CONSTRAINT "weeks_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_attendance_directory_member_id" ON "public"."attendance" USING "btree" ("directory_member_id");



CREATE INDEX "idx_attendance_week" ON "public"."attendance" USING "btree" ("week_id");



CREATE INDEX "idx_attendance_week_id" ON "public"."attendance" USING "btree" ("week_id");



CREATE INDEX "idx_groups_church" ON "public"."groups" USING "btree" ("church_id");



CREATE INDEX "idx_member_directory_church_id" ON "public"."member_directory" USING "btree" ("church_id");



CREATE INDEX "idx_member_directory_department_id" ON "public"."member_directory" USING "btree" ("department_id");



CREATE INDEX "idx_member_directory_group_name" ON "public"."member_directory" USING "btree" ("group_name");



CREATE INDEX "idx_member_directory_is_active" ON "public"."member_directory" USING "btree" ("is_active");



CREATE INDEX "idx_notice_reads_user_id" ON "public"."notice_reads" USING "btree" ("user_id");



CREATE INDEX "idx_prayer_entries_directory_member_id" ON "public"."prayer_entries" USING "btree" ("directory_member_id");



CREATE INDEX "idx_prayer_entries_status" ON "public"."prayer_entries" USING "btree" ("status");



CREATE INDEX "idx_prayer_entries_week_group" ON "public"."prayer_entries" USING "btree" ("week_id", "group_id");



CREATE INDEX "idx_prayer_entries_week_id" ON "public"."prayer_entries" USING "btree" ("week_id");



CREATE INDEX "idx_prayer_interactions_prayer_id" ON "public"."prayer_interactions" USING "btree" ("prayer_id");



CREATE INDEX "idx_prayer_interactions_profile_id" ON "public"."prayer_interactions" USING "btree" ("profile_id");



CREATE INDEX "idx_profiles_church" ON "public"."profiles" USING "btree" ("church_id");



CREATE INDEX "idx_profiles_church_id" ON "public"."profiles" USING "btree" ("church_id");



CREATE INDEX "idx_profiles_department_id" ON "public"."profiles" USING "btree" ("department_id");



CREATE INDEX "idx_weeks_church_id" ON "public"."weeks" USING "btree" ("church_id");



CREATE INDEX "idx_weeks_week_date" ON "public"."weeks" USING "btree" ("week_date");



CREATE OR REPLACE TRIGGER "on_directory_group_change" AFTER UPDATE OF "group_name", "profile_id" ON "public"."member_directory" FOR EACH ROW EXECUTE FUNCTION "public"."sync_directory_to_group_members"();



CREATE OR REPLACE TRIGGER "on_inquiry_insert_sync_church" BEFORE INSERT ON "public"."inquiries" FOR EACH ROW EXECUTE FUNCTION "public"."manage_inquiry_unread_flags"();



CREATE OR REPLACE TRIGGER "on_inquiry_response_created" AFTER INSERT ON "public"."inquiry_responses" FOR EACH ROW EXECUTE FUNCTION "public"."handle_inquiry_response_updated_at"();



CREATE OR REPLACE TRIGGER "on_inquiry_response_inserted" AFTER INSERT ON "public"."inquiry_responses" FOR EACH ROW EXECUTE FUNCTION "public"."handle_inquiry_response_flags"();



CREATE OR REPLACE TRIGGER "on_member_data_update" AFTER UPDATE OF "full_name", "phone", "spouse_name", "children_info", "birth_date", "wedding_anniversary", "notes", "avatar_url", "profile_id", "is_linked" ON "public"."member_directory" FOR EACH ROW EXECUTE FUNCTION "public"."sync_person_data"();



CREATE OR REPLACE TRIGGER "on_member_directory_membership_sync" AFTER INSERT OR UPDATE OF "profile_id", "group_name", "role_in_group", "is_active" ON "public"."member_directory" FOR EACH ROW EXECUTE FUNCTION "public"."sync_directory_to_group_members"();



CREATE OR REPLACE TRIGGER "on_member_directory_profile_sync_by_phone" BEFORE INSERT OR UPDATE OF "phone", "profile_id" ON "public"."member_directory" FOR EACH ROW EXECUTE FUNCTION "public"."sync_profile_id_by_phone"();



CREATE OR REPLACE TRIGGER "on_member_insert_assign_person_id" BEFORE INSERT ON "public"."member_directory" FOR EACH ROW EXECUTE FUNCTION "public"."handle_member_person_id_assignment"();



CREATE OR REPLACE TRIGGER "on_member_profile_linked" AFTER UPDATE OF "profile_id" ON "public"."member_directory" FOR EACH ROW WHEN ((("old"."profile_id" IS NULL) AND ("new"."profile_id" IS NOT NULL))) EXECUTE FUNCTION "public"."sync_member_linkage_to_others"();



CREATE OR REPLACE TRIGGER "on_member_profile_unlinked" BEFORE UPDATE OF "profile_id" ON "public"."member_directory" FOR EACH ROW WHEN ((("old"."profile_id" IS NOT NULL) AND ("new"."profile_id" IS NULL))) EXECUTE FUNCTION "public"."handle_member_directory_unlinking"();



CREATE OR REPLACE TRIGGER "on_member_update_assign_person_id" BEFORE UPDATE ON "public"."member_directory" FOR EACH ROW WHEN ((("new"."person_id" IS NULL) AND (("new"."full_name" IS NOT NULL) AND ("new"."phone" IS NOT NULL)))) EXECUTE FUNCTION "public"."handle_member_person_id_assignment"();



CREATE OR REPLACE TRIGGER "on_notices_updated" BEFORE UPDATE ON "public"."notices" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();



CREATE OR REPLACE TRIGGER "on_prayer_interaction_changed" AFTER INSERT OR DELETE ON "public"."prayer_interactions" FOR EACH ROW EXECUTE FUNCTION "public"."handle_prayer_interaction_count"();



CREATE OR REPLACE TRIGGER "on_profile_data_update" AFTER UPDATE OF "full_name", "phone", "avatar_url", "wedding_anniversary", "children_info", "notes" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."sync_profile_to_member"();



CREATE OR REPLACE TRIGGER "on_profile_upsert_assign_person_id" BEFORE INSERT OR UPDATE OF "phone", "full_name" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_profile_upsert_assign_person_id"();



CREATE OR REPLACE TRIGGER "sync_profile_to_memberships_trigger" AFTER INSERT OR UPDATE OF "person_id", "full_name", "phone" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."sync_profile_to_all_memberships"();



CREATE OR REPLACE TRIGGER "tr_member_directory_phone_uniqueness" BEFORE INSERT OR UPDATE OF "phone" ON "public"."member_directory" FOR EACH ROW EXECUTE FUNCTION "public"."check_phone_uniqueness"();



ALTER TABLE ONLY "public"."attendance"
    ADD CONSTRAINT "attendance_directory_member_id_fkey" FOREIGN KEY ("directory_member_id") REFERENCES "public"."member_directory"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance"
    ADD CONSTRAINT "attendance_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."attendance"
    ADD CONSTRAINT "attendance_group_member_id_fkey" FOREIGN KEY ("group_member_id") REFERENCES "public"."group_members"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance"
    ADD CONSTRAINT "attendance_week_id_fkey" FOREIGN KEY ("week_id") REFERENCES "public"."weeks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."families"
    ADD CONSTRAINT "families_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."families"
    ADD CONSTRAINT "families_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inquiries"
    ADD CONSTRAINT "inquiries_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inquiries"
    ADD CONSTRAINT "inquiries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inquiry_responses"
    ADD CONSTRAINT "inquiry_responses_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inquiry_responses"
    ADD CONSTRAINT "inquiry_responses_inquiry_id_fkey" FOREIGN KEY ("inquiry_id") REFERENCES "public"."inquiries"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."member_directory"
    ADD CONSTRAINT "member_directory_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."member_directory"
    ADD CONSTRAINT "member_directory_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."member_directory"
    ADD CONSTRAINT "member_directory_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."newsletters"
    ADD CONSTRAINT "newsletters_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."newsletters"
    ADD CONSTRAINT "newsletters_week_id_fkey" FOREIGN KEY ("week_id") REFERENCES "public"."weeks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notice_reads"
    ADD CONSTRAINT "notice_reads_notice_id_fkey" FOREIGN KEY ("notice_id") REFERENCES "public"."notices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notice_reads"
    ADD CONSTRAINT "notice_reads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notices"
    ADD CONSTRAINT "notices_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notices"
    ADD CONSTRAINT "notices_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notices"
    ADD CONSTRAINT "notices_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prayer_ai_backups"
    ADD CONSTRAINT "prayer_ai_backups_prayer_entry_id_fkey" FOREIGN KEY ("prayer_entry_id") REFERENCES "public"."prayer_entries"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prayer_entries"
    ADD CONSTRAINT "prayer_entries_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."prayer_entries"
    ADD CONSTRAINT "prayer_entries_directory_member_id_fkey" FOREIGN KEY ("directory_member_id") REFERENCES "public"."member_directory"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prayer_entries"
    ADD CONSTRAINT "prayer_entries_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prayer_entries"
    ADD CONSTRAINT "prayer_entries_member_id_fkey" FOREIGN KEY ("member_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."prayer_entries"
    ADD CONSTRAINT "prayer_entries_week_id_fkey" FOREIGN KEY ("week_id") REFERENCES "public"."weeks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prayer_interactions"
    ADD CONSTRAINT "prayer_interactions_prayer_id_fkey" FOREIGN KEY ("prayer_id") REFERENCES "public"."prayer_entries"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prayer_interactions"
    ADD CONSTRAINT "prayer_interactions_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_family_id_fkey" FOREIGN KEY ("family_id") REFERENCES "public"."families"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_spouse_id_fkey" FOREIGN KEY ("spouse_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."weeks"
    ADD CONSTRAINT "weeks_church_id_fkey" FOREIGN KEY ("church_id") REFERENCES "public"."churches"("id") ON DELETE CASCADE;



CREATE POLICY "Attendance church isolation" ON "public"."attendance" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."weeks" "w"
  WHERE (("w"."id" = "attendance"."week_id") AND (("w"."church_id" = "public"."get_my_church_id"()) OR "public"."check_is_master"())))));



CREATE POLICY "Attendance manage" ON "public"."attendance" TO "authenticated" USING (("public"."is_admin_approved"() OR "public"."is_leader"() OR "public"."check_is_master"())) WITH CHECK (("public"."is_admin_approved"() OR "public"."is_leader"() OR "public"."check_is_master"()));



CREATE POLICY "Churches master manage" ON "public"."churches" TO "authenticated" USING ("public"."check_is_master"()) WITH CHECK ("public"."check_is_master"());



CREATE POLICY "Churches select all" ON "public"."churches" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Debug logs master manage" ON "public"."debug_logs" TO "authenticated" USING ("public"."check_is_master"()) WITH CHECK ("public"."check_is_master"());



CREATE POLICY "Depts admin manage" ON "public"."departments" TO "authenticated" USING (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"())) WITH CHECK (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"()));



CREATE POLICY "Depts church isolation" ON "public"."departments" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Directory admin manage" ON "public"."member_directory" TO "authenticated" USING (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"())) WITH CHECK (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"()));



CREATE POLICY "Directory church isolation" ON "public"."member_directory" FOR SELECT TO "authenticated" USING ((("church_id" = "public"."get_my_church_id"()) OR ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."is_onboarding_complete" = false)))) AND ("phone" = ( SELECT "profiles"."phone"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))) OR "public"."check_is_master"()));



CREATE POLICY "Families admin manage" ON "public"."families" TO "authenticated" USING (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"())) WITH CHECK (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"()));



CREATE POLICY "Families church isolation" ON "public"."families" FOR SELECT TO "authenticated" USING ((("church_id" = "public"."get_my_church_id"()) OR "public"."check_is_master"()));



CREATE POLICY "Groups admin manage" ON "public"."groups" TO "authenticated" USING (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"())) WITH CHECK (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"()));



CREATE POLICY "Groups church isolation" ON "public"."groups" FOR SELECT TO "authenticated" USING ((("church_id" = "public"."get_my_church_id"()) OR ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."is_onboarding_complete" = false)))) AND ("church_id" = "public"."get_my_matched_church_id"())) OR "public"."check_is_master"()));



CREATE POLICY "Inquiries self/master" ON "public"."inquiries" TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."check_is_master"())) WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."check_is_master"()));



CREATE POLICY "Inquiry responses master all" ON "public"."inquiry_responses" TO "authenticated" USING ("public"."check_is_master"()) WITH CHECK ("public"."check_is_master"());



CREATE POLICY "Inquiry responses self/master" ON "public"."inquiry_responses" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."inquiries" "i"
  WHERE (("i"."id" = "inquiry_responses"."inquiry_id") AND (("i"."user_id" = "auth"."uid"()) OR "public"."check_is_master"())))));



CREATE POLICY "Interactions self" ON "public"."prayer_interactions" TO "authenticated" USING ((("profile_id" = "auth"."uid"()) OR "public"."check_is_master"())) WITH CHECK ((("profile_id" = "auth"."uid"()) OR "public"."check_is_master"()));



CREATE POLICY "Leaders manage directory" ON "public"."member_directory" TO "authenticated" USING ("public"."check_group_leader_permission"("church_id", "department_id", "group_name")) WITH CHECK ("public"."check_group_leader_permission"("church_id", "department_id", "group_name"));



CREATE POLICY "Membership admin manage" ON "public"."group_members" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."groups" "gma_g"
  WHERE (("gma_g"."id" = "group_members"."group_id") AND ("public"."is_admin_approved"("gma_g"."church_id") OR "public"."check_is_master"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."groups" "gma_g"
  WHERE (("gma_g"."id" = "group_members"."group_id") AND ("public"."is_admin_approved"("gma_g"."church_id") OR "public"."check_is_master"())))));



CREATE POLICY "Membership church isolation" ON "public"."group_members" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."groups" "g"
  WHERE (("g"."id" = "group_members"."group_id") AND (("g"."church_id" = "public"."get_my_church_id"()) OR "public"."check_is_master"())))));



CREATE POLICY "Membership claim and manage" ON "public"."group_members" TO "authenticated" USING ((("profile_id" = "auth"."uid"()) OR (("profile_id" IS NULL) AND ("member_directory_id" IN ( SELECT "md"."id"
   FROM ("public"."member_directory" "md"
     JOIN "public"."profiles" "p" ON (("md"."person_id" = "p"."person_id")))
  WHERE ("p"."id" = "auth"."uid"())))) OR "public"."check_is_master"())) WITH CHECK ((("profile_id" = "auth"."uid"()) OR "public"."check_is_master"()));



CREATE POLICY "Membership self manage" ON "public"."group_members" TO "authenticated" USING ((("profile_id" = "auth"."uid"()) OR "public"."check_is_master"())) WITH CHECK ((("profile_id" = "auth"."uid"()) OR "public"."check_is_master"()));



CREATE POLICY "Newsletters select all" ON "public"."newsletters" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Notice reads self manage" ON "public"."notice_reads" TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."check_is_master"())) WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."check_is_master"()));



CREATE POLICY "Notices admin manage" ON "public"."notices" TO "authenticated" USING (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"())) WITH CHECK (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"()));



CREATE POLICY "Notices church isolation" ON "public"."notices" FOR SELECT TO "authenticated" USING ((("is_global" = true) OR ("church_id" = "public"."get_my_church_id"()) OR "public"."check_is_master"()));



CREATE POLICY "Phone verifications self manage" ON "public"."phone_verifications" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Prayers church isolation" ON "public"."prayer_entries" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."weeks" "w"
  WHERE (("w"."id" = "prayer_entries"."week_id") AND (("w"."church_id" = "public"."get_my_church_id"()) OR "public"."check_is_master"())))));



CREATE POLICY "Prayers self/admin manage" ON "public"."prayer_entries" TO "authenticated" USING ((("member_id" = "auth"."uid"()) OR "public"."is_admin_approved"() OR "public"."is_leader"() OR "public"."check_is_master"())) WITH CHECK ((("member_id" = "auth"."uid"()) OR "public"."is_admin_approved"() OR "public"."is_leader"() OR "public"."check_is_master"()));



CREATE POLICY "Profiles church select" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("church_id" = "public"."get_my_church_id"()) OR "public"."check_is_master"()));



CREATE POLICY "Profiles self all" ON "public"."profiles" TO "authenticated" USING ((("auth"."uid"() = "id") OR "public"."check_is_master"())) WITH CHECK ((("auth"."uid"() = "id") OR "public"."check_is_master"()));



CREATE POLICY "Users can insert responses to their own inquiries" ON "public"."inquiry_responses" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."inquiries" "i"
  WHERE (("i"."id" = "inquiry_responses"."inquiry_id") AND ("i"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view their own directory records" ON "public"."member_directory" FOR SELECT TO "authenticated" USING ((("profile_id" = "auth"."uid"()) OR ("person_id" IN ( SELECT "profiles"."person_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) OR "public"."check_is_master"()));



CREATE POLICY "Weeks admin manage" ON "public"."weeks" TO "authenticated" USING (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"())) WITH CHECK (("public"."is_admin_approved"("church_id") OR "public"."check_is_master"()));



CREATE POLICY "Weeks church isolation" ON "public"."weeks" FOR SELECT TO "authenticated" USING ((("church_id" = "public"."get_my_church_id"()) OR "public"."check_is_master"()));



ALTER TABLE "public"."attendance" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."churches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."debug_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."departments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."families" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."group_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."groups" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inquiries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inquiry_responses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."member_directory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."newsletters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notice_reads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."phone_verifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prayer_ai_backups" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prayer_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prayer_interactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."weeks" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."group_members";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."inquiries";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."inquiry_responses";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."member_directory";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notice_reads";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notices";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."check_group_leader_permission"("target_church_id" "uuid", "target_department_id" "uuid", "target_group_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_group_leader_permission"("target_church_id" "uuid", "target_department_id" "uuid", "target_group_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_group_leader_permission"("target_church_id" "uuid", "target_department_id" "uuid", "target_group_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_is_master"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_is_master"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_is_master"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_phone_exists"("p_phone" "text", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_phone_exists"("p_phone" "text", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_phone_exists"("p_phone" "text", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_phone_uniqueness"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_phone_uniqueness"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_phone_uniqueness"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_orphaned_users"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_users"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_users"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_together_count"("row_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_together_count"("row_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_together_count"("row_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_self_in_onboarding"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_self_in_onboarding"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_self_in_onboarding"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_week_exists"("p_church_id" "uuid", "p_week_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_week_exists"("p_church_id" "uuid", "p_week_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_week_exists"("p_church_id" "uuid", "p_week_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_church_member_counts"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_church_member_counts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_church_member_counts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_church_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_church_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_church_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_matched_church_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_matched_church_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_matched_church_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_profile"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_or_create_person_id"("p_full_name" "text", "p_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_or_create_person_id"("p_full_name" "text", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_person_id"("p_full_name" "text", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_inquiry_response_flags"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_inquiry_response_flags"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_inquiry_response_flags"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_inquiry_response_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_inquiry_response_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_inquiry_response_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_member_directory_unlinking"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_member_directory_unlinking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_member_directory_unlinking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_member_person_id_assignment"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_member_person_id_assignment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_member_person_id_assignment"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user_profile"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_prayer_interaction_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_prayer_interaction_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_prayer_interaction_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_profile_person_id_assignment"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_profile_person_id_assignment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_profile_person_id_assignment"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_profile_upsert_assign_person_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_profile_upsert_assign_person_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_profile_upsert_assign_person_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_together_count"("row_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_together_count"("row_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_together_count"("row_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin_approved"("target_church_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin_approved"("target_church_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin_approved"("target_church_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_in_church"("target_church_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_in_church"("target_church_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_in_church"("target_church_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_leader"("target_church_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_leader"("target_church_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_leader"("target_church_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."manage_inquiry_unread_flags"() TO "anon";
GRANT ALL ON FUNCTION "public"."manage_inquiry_unread_flags"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."manage_inquiry_unread_flags"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mask_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mask_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mask_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."regroup_members"("p_member_ids" "uuid"[], "p_target_group_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."regroup_members"("p_member_ids" "uuid"[], "p_target_group_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."regroup_members"("p_member_ids" "uuid"[], "p_target_group_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."submit_admin_request"("p_full_name" "text", "p_church_id" "uuid", "p_department_id" "uuid", "p_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."submit_admin_request"("p_full_name" "text", "p_church_id" "uuid", "p_department_id" "uuid", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_admin_request"("p_full_name" "text", "p_church_id" "uuid", "p_department_id" "uuid", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_directory_to_group_members"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_directory_to_group_members"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_directory_to_group_members"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_inquiry_church_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_inquiry_church_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_inquiry_church_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_member_linkage_to_others"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_member_linkage_to_others"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_member_linkage_to_others"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_person_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_person_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_person_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_profile_and_directory_by_phone"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_profile_and_directory_by_phone"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_profile_and_directory_by_phone"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_profile_id_by_phone"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_profile_id_by_phone"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_profile_id_by_phone"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_profile_id_to_group_members"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_profile_id_to_group_members"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_profile_id_to_group_members"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_profile_to_all_memberships"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_profile_to_all_memberships"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_profile_to_all_memberships"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_profile_to_member"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_profile_to_member"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_profile_to_member"() TO "service_role";


















GRANT ALL ON TABLE "public"."attendance" TO "anon";
GRANT ALL ON TABLE "public"."attendance" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance" TO "service_role";



GRANT ALL ON TABLE "public"."churches" TO "anon";
GRANT ALL ON TABLE "public"."churches" TO "authenticated";
GRANT ALL ON TABLE "public"."churches" TO "service_role";



GRANT ALL ON TABLE "public"."debug_logs" TO "anon";
GRANT ALL ON TABLE "public"."debug_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."debug_logs" TO "service_role";



GRANT ALL ON SEQUENCE "public"."debug_logs_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."debug_logs_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."debug_logs_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."departments" TO "anon";
GRANT ALL ON TABLE "public"."departments" TO "authenticated";
GRANT ALL ON TABLE "public"."departments" TO "service_role";



GRANT ALL ON TABLE "public"."families" TO "anon";
GRANT ALL ON TABLE "public"."families" TO "authenticated";
GRANT ALL ON TABLE "public"."families" TO "service_role";



GRANT ALL ON TABLE "public"."group_members" TO "anon";
GRANT ALL ON TABLE "public"."group_members" TO "authenticated";
GRANT ALL ON TABLE "public"."group_members" TO "service_role";



GRANT ALL ON TABLE "public"."groups" TO "anon";
GRANT ALL ON TABLE "public"."groups" TO "authenticated";
GRANT ALL ON TABLE "public"."groups" TO "service_role";



GRANT ALL ON TABLE "public"."inquiries" TO "anon";
GRANT ALL ON TABLE "public"."inquiries" TO "authenticated";
GRANT ALL ON TABLE "public"."inquiries" TO "service_role";



GRANT ALL ON TABLE "public"."inquiry_responses" TO "anon";
GRANT ALL ON TABLE "public"."inquiry_responses" TO "authenticated";
GRANT ALL ON TABLE "public"."inquiry_responses" TO "service_role";



GRANT ALL ON TABLE "public"."member_directory" TO "anon";
GRANT ALL ON TABLE "public"."member_directory" TO "authenticated";
GRANT ALL ON TABLE "public"."member_directory" TO "service_role";



GRANT ALL ON TABLE "public"."newsletters" TO "anon";
GRANT ALL ON TABLE "public"."newsletters" TO "authenticated";
GRANT ALL ON TABLE "public"."newsletters" TO "service_role";



GRANT ALL ON TABLE "public"."notice_reads" TO "anon";
GRANT ALL ON TABLE "public"."notice_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."notice_reads" TO "service_role";



GRANT ALL ON TABLE "public"."notices" TO "anon";
GRANT ALL ON TABLE "public"."notices" TO "authenticated";
GRANT ALL ON TABLE "public"."notices" TO "service_role";



GRANT ALL ON TABLE "public"."phone_verifications" TO "anon";
GRANT ALL ON TABLE "public"."phone_verifications" TO "authenticated";
GRANT ALL ON TABLE "public"."phone_verifications" TO "service_role";



GRANT ALL ON TABLE "public"."prayer_ai_backups" TO "anon";
GRANT ALL ON TABLE "public"."prayer_ai_backups" TO "authenticated";
GRANT ALL ON TABLE "public"."prayer_ai_backups" TO "service_role";



GRANT ALL ON TABLE "public"."prayer_entries" TO "anon";
GRANT ALL ON TABLE "public"."prayer_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."prayer_entries" TO "service_role";



GRANT ALL ON TABLE "public"."prayer_interactions" TO "anon";
GRANT ALL ON TABLE "public"."prayer_interactions" TO "authenticated";
GRANT ALL ON TABLE "public"."prayer_interactions" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."public_church_list" TO "anon";
GRANT ALL ON TABLE "public"."public_church_list" TO "authenticated";
GRANT ALL ON TABLE "public"."public_church_list" TO "service_role";



GRANT ALL ON TABLE "public"."public_department_list" TO "anon";
GRANT ALL ON TABLE "public"."public_department_list" TO "authenticated";
GRANT ALL ON TABLE "public"."public_department_list" TO "service_role";



GRANT ALL ON TABLE "public"."weeks" TO "anon";
GRANT ALL ON TABLE "public"."weeks" TO "authenticated";
GRANT ALL ON TABLE "public"."weeks" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































