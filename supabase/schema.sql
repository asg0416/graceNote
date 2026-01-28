-- Grace Note - 최종 통합 마스터 스키마 (Consolidated Master Schema)
-- 이 파일은 수동으로 나뉘어 있던 5개의 SQL 조각을 하나로 통합한 최종 버전입니다.
-- 초기화, 테이블 정의, 제약 조건 최적화, 트리거 및 RLS 정책을 모두 포함합니다.

-- ============================================
-- STEP 1: 전체 초기화 및 확장 기능 설정
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$
DECLARE
    pol RECORD;
BEGIN
    -- 1. 기존 RLS 정책 전체 삭제 (초기화)
    FOR pol IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
    END LOOP;

    -- 2. 제약 조건 충돌 해결
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_admin_status_check;


    -- 3. 기존 'user'로 잘못 생성된 데이터를 'member'로 일괄 변경
    UPDATE public.profiles SET role = 'member' WHERE role = 'user';
EXCEPTION WHEN OTHERS THEN 
    RAISE NOTICE 'Notice: Initial cleanup info: %', SQLERRM;
END $$;

-- 디버깅용 테이블 (프로필 생성 실패 시 원인 추적용)
CREATE TABLE IF NOT EXISTS public.debug_logs (
    id SERIAL PRIMARY KEY,
    level TEXT,
    message TEXT,
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- STEP 2: 핵심 보안 및 유틸리티 함수 (RPC)
-- ============================================

-- 마스터 권한 확인
CREATE OR REPLACE FUNCTION public.check_is_master()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND is_master = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 승인된 관리자 확인
CREATE OR REPLACE FUNCTION public.is_admin_approved(target_church_id UUID DEFAULT NULL)
RETURNS BOOLEAN AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 조장 확인
CREATE OR REPLACE FUNCTION public.is_leader(target_church_id UUID DEFAULT NULL)
RETURNS BOOLEAN AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 내 프로필 조회 RPC
CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS TABLE (id UUID, full_name TEXT, role TEXT, admin_status TEXT, is_master BOOLEAN, church_id UUID) AS $$
BEGIN
  RETURN QUERY SELECT p.id, p.full_name, p.role, p.admin_status, p.is_master, p.church_id 
  FROM public.profiles p WHERE p.id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 교회 인원 통계 RPC
CREATE OR REPLACE FUNCTION public.get_church_member_counts()
RETURNS TABLE (church_id UUID, member_count INT) AS $$
BEGIN
  RETURN QUERY
  SELECT p.church_id, COUNT(*)::INT as member_count
  FROM public.profiles p
  WHERE p.church_id IS NOT NULL
  GROUP BY p.church_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 함께 기도 카운트 증가 RPC
CREATE OR REPLACE FUNCTION public.increment_together_count(row_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.prayer_entries
  SET together_count = COALESCE(together_count, 0) + 1
  WHERE id = row_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 함께 기도 카운트 감소 RPC
CREATE OR REPLACE FUNCTION public.decrement_together_count(row_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.prayer_entries
  SET together_count = GREATEST(COALESCE(together_count, 0) - 1, 0)
  WHERE id = row_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- STEP 3: 테이블 정의 및 컬럼 설정
-- ============================================

-- 1. 교회 (Churches)
CREATE TABLE IF NOT EXISTS churches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT,
    settings JSONB DEFAULT '{"allow_leader_cross_view": false}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 부서 (Departments)
CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    profile_mode TEXT DEFAULT 'individual' CHECK (profile_mode IN ('individual', 'couple')),
    allow_late_entry BOOLEAN DEFAULT true,
    color_hex TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 가족 (Families)
CREATE TABLE IF NOT EXISTS families (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. 프로필 (Profiles)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT,
    church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    family_id UUID REFERENCES families(id) ON DELETE SET NULL,
    spouse_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    admin_status TEXT DEFAULT 'none' CHECK (admin_status IN ('none', 'pending', 'approved', 'rejected')),
    is_master BOOLEAN DEFAULT FALSE,
    phone TEXT UNIQUE, -- Added UNIQUE constraint
    wedding_anniversary DATE,
    birth_date DATE,
    children_info TEXT,
    notes TEXT,
    is_onboarding_complete BOOLEAN DEFAULT FALSE,
    avatar_url TEXT,
    last_notice_checked_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. 소그룹/조 (Groups)
CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color_hex TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(church_id, department_id, name)
);

-- 6. 소그룹 소속 (Group Members)
CREATE TABLE IF NOT EXISTS group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
    profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    role_in_group TEXT DEFAULT 'member',
    is_active BOOLEAN DEFAULT true,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(group_id, profile_id)
);

-- 7. 주차 관리 (Weeks)
CREATE TABLE IF NOT EXISTS weeks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
    week_date DATE NOT NULL,
    name TEXT,
    UNIQUE(church_id, week_date)
);

-- 8. 출석 기록 (Attendance)
CREATE TABLE IF NOT EXISTS attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    week_id UUID REFERENCES weeks(id) ON DELETE CASCADE,
    group_member_id UUID REFERENCES group_members(id) ON DELETE SET NULL,
    directory_member_id UUID REFERENCES member_directory(id) ON DELETE CASCADE,
    status TEXT CHECK (status IN ('present', 'absent', 'excused')) DEFAULT 'absent',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(week_id, directory_member_id)
);

-- 9. 성도 명부 (Member Directory)
CREATE TABLE IF NOT EXISTS member_directory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone TEXT,
    group_name TEXT,
    role_in_group TEXT DEFAULT 'member',
    family_name TEXT,
    spouse_name TEXT,
    children_info TEXT,
    notes TEXT,
    family_id UUID REFERENCES families(id) ON DELETE SET NULL,
    profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    is_linked BOOLEAN DEFAULT FALSE,
    wedding_anniversary DATE,
    birth_date DATE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(church_id, department_id, group_name, full_name)
);

-- 10. 기도 제목 (Prayer Entries)
CREATE TABLE IF NOT EXISTS prayer_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    week_id UUID REFERENCES weeks(id) ON DELETE CASCADE,
    group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
    author_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    member_id UUID REFERENCES profiles(id) ON DELETE SET NULL, -- New primary source (Legacy link)
    directory_member_id UUID REFERENCES member_directory(id) ON DELETE CASCADE, -- New primary source
    content TEXT,
    ai_refined_content TEXT,
    status TEXT CHECK (status IN ('draft', 'published')) DEFAULT 'draft',
    together_count INTEGER DEFAULT 0,
    is_refining BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(week_id, directory_member_id)
);

-- 11. 기도 상호작용 (Prayer Interactions)
CREATE TABLE IF NOT EXISTS prayer_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prayer_id UUID REFERENCES prayer_entries(id) ON DELETE CASCADE,
    profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    interaction_type TEXT CHECK (interaction_type IN ('pray', 'save')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(prayer_id, profile_id, interaction_type)
);

-- 12. 주보/뉴스레터 (Newsletters)
CREATE TABLE IF NOT EXISTS newsletters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
    week_id UUID REFERENCES weeks(id) ON DELETE CASCADE,
    content TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. 기도 제목 AI 백업
CREATE TABLE IF NOT EXISTS prayer_ai_backups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prayer_entry_id UUID REFERENCES prayer_entries(id) ON DELETE CASCADE,
    original_content TEXT,
    refined_content TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. 공지사항 (Notices)
CREATE TABLE IF NOT EXISTS public.notices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'general',
    is_global BOOLEAN DEFAULT false,
    target_role TEXT DEFAULT 'all',
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. 문의하기 (Inquiries)
CREATE TABLE IF NOT EXISTS public.inquiries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT DEFAULT 'bug',
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'replied', 'closed')),
    user_last_read_at TIMESTAMPTZ,
    admin_last_read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 15. 문의 답변 (Inquiry Responses)
CREATE TABLE IF NOT EXISTS public.inquiry_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inquiry_id UUID REFERENCES public.inquiries(id) ON DELETE CASCADE,
    admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 문의 답변 시 문의글의 updated_at 자동 갱신 트리거
CREATE OR REPLACE FUNCTION public.handle_inquiry_response_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.inquiries
  SET updated_at = NOW()
  WHERE id = NEW.inquiry_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_inquiry_response_inserted ON public.inquiry_responses;
CREATE TRIGGER on_inquiry_response_inserted
AFTER INSERT ON public.inquiry_responses
FOR EACH ROW EXECUTE FUNCTION public.handle_inquiry_response_updated_at();

-- ============================================
-- STEP 4: 컬럼 강제 동기화 (기존 테이블 업데이트용)
-- ============================================
DO $$
BEGIN
    -- Departments
    ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS profile_mode TEXT DEFAULT 'individual';
    ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS color_hex TEXT;
    ALTER TABLE public.departments DROP CONSTRAINT IF EXISTS departments_profile_mode_check;
    ALTER TABLE public.departments ADD CONSTRAINT departments_profile_mode_check CHECK (profile_mode IN ('individual', 'couple'));

    -- Groups
    ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS color_hex TEXT;

    -- Profiles
    ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS notes TEXT;
    ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_church_id_fkey;
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_church_id_fkey FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE;
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_spouse_id_fkey;
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_spouse_id_fkey FOREIGN KEY (spouse_id) REFERENCES profiles(id) ON DELETE SET NULL;

    -- Member Directory
    ALTER TABLE public.member_directory ADD COLUMN IF NOT EXISTS notes TEXT;
    ALTER TABLE public.member_directory ADD COLUMN IF NOT EXISTS avatar_url TEXT;
    ALTER TABLE public.member_directory DROP CONSTRAINT IF EXISTS member_directory_unique_assignment;
    ALTER TABLE public.member_directory ADD CONSTRAINT member_directory_unique_assignment UNIQUE (church_id, department_id, group_name, full_name);

EXCEPTION WHEN OTHERS THEN 
    RAISE NOTICE 'Migration guard info: %', SQLERRM;
END $$;

-- ============================================
-- STEP 5: 보안 뷰 및 권한
-- ============================================

CREATE OR REPLACE VIEW public_church_list AS
SELECT id, name FROM public.churches;

GRANT SELECT ON public_church_list TO anon;
GRANT SELECT ON public_church_list TO authenticated;

-- Create a public view for departments to be used during registration
CREATE OR REPLACE VIEW public_department_list AS
SELECT id, church_id, name FROM public.departments;

GRANT SELECT ON public_department_list TO anon;
GRANT SELECT ON public_department_list TO authenticated;

-- ============================================
-- STEP 6: 트리거 (회원가입 자동 프로필 생성)
-- ============================================

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
  v_email TEXT;
BEGIN
  IF (NEW.raw_user_meta_data->>'role_request' = 'admin') OR (NEW.raw_user_meta_data->>'roleRequest' = 'admin') THEN
    v_role := 'admin';
    v_status := 'pending';
  ELSE
    v_role := 'member';
    v_status := 'none';
  END IF;

  v_full_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name', 
    NEW.raw_user_meta_data->>'fullName', 
    '신규 유저'
  );

  v_phone := NEW.raw_user_meta_data->>'phone';
  v_email := NEW.email;

  v_raw_church_id := NULLIF(TRIM(NEW.raw_user_meta_data->>'church_id'), '');
  v_raw_dept_id := NULLIF(TRIM(NEW.raw_user_meta_data->>'department_id'), '');
  
  -- Church ID processing
  IF (v_raw_church_id IS NOT NULL AND v_raw_church_id <> 'null') THEN
    IF (v_raw_church_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') THEN
      SELECT id INTO v_church_id FROM public.churches WHERE id = v_raw_church_id::UUID;
    ELSE
      SELECT id INTO v_church_id FROM public.churches WHERE name = v_raw_church_id LIMIT 1;
    END IF;
  END IF;

  -- Department ID processing
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
    RAISE EXCEPTION 'This phone number is already registered.';
  WHEN OTHERS THEN
    INSERT INTO public.debug_logs (level, message, payload)
    VALUES ('ERROR', 'Profile Trigger Failed: ' || SQLERRM, jsonb_build_object('user_id', NEW.id));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- ============================================
-- STEP 7: RLS (Row Level Security) 정책 적용
-- ============================================

DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    END LOOP;
END $$;

-- [Profiles]
CREATE POLICY "Profiles select all" ON profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Profiles self insert" ON profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "Profiles self update" ON profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "Profiles master all" ON profiles FOR ALL TO authenticated USING (public.check_is_master());

-- [교회 / 그룹 / 부서 / 가족]
CREATE POLICY "View churches" ON churches FOR SELECT TO authenticated USING (true);
CREATE POLICY "Master manage churches" ON churches FOR ALL TO authenticated USING (public.check_is_master());
CREATE POLICY "View departments" ON departments FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage departments" ON departments FOR ALL TO authenticated USING (public.is_admin_approved(church_id));
CREATE POLICY "View groups" ON groups FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage groups" ON groups FOR ALL TO authenticated USING (public.is_admin_approved(church_id));
CREATE POLICY "View families" ON families FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage families" ON families FOR ALL TO authenticated USING (public.is_admin_approved(church_id));

-- [Membership]
CREATE POLICY "Users handle own membership" ON group_members FOR ALL TO authenticated USING (profile_id = auth.uid()) WITH CHECK (profile_id = auth.uid());
CREATE POLICY "Admins handle group members" ON group_members FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM groups g WHERE g.id = group_members.group_id AND public.is_admin_approved(g.church_id)));
CREATE POLICY "View membership" ON group_members FOR SELECT TO authenticated USING (true);

-- [Weeks / Attendance / Prayers / Newsletters / Directory]
CREATE POLICY "View weeks" ON weeks FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins and Leaders manage weeks" ON weeks FOR ALL TO authenticated 
USING (public.is_admin_approved(church_id) OR public.is_leader(church_id));
CREATE POLICY "View attendance" ON attendance FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins and Leaders manage attendance" ON attendance FOR ALL TO authenticated 
USING (public.is_admin_approved() OR public.is_leader());
CREATE POLICY "View prayers" ON prayer_entries FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins and Leaders manage group prayers" ON prayer_entries FOR ALL TO authenticated 
USING (public.is_admin_approved() OR public.is_leader());
CREATE POLICY "Members manage own prayers" ON prayer_entries FOR ALL TO authenticated 
USING (member_id = auth.uid()) WITH CHECK (member_id = auth.uid());
CREATE POLICY "View newsletters" ON newsletters FOR SELECT TO authenticated USING (true);
-- [Directory Policy]
CREATE POLICY "Admins manage directory" ON member_directory FOR ALL TO authenticated USING (public.is_admin_approved(church_id)) WITH CHECK (public.is_admin_approved(church_id));
CREATE POLICY "View directory" ON member_directory FOR SELECT TO authenticated USING (true);

-- [Notices]
CREATE POLICY "View notices" ON notices FOR SELECT TO authenticated USING (
    is_global = true OR church_id = (SELECT church_id FROM profiles WHERE id = auth.uid()) OR public.check_is_master()
);
CREATE POLICY "Manage notices" ON notices FOR ALL TO authenticated USING (
    public.check_is_master() OR public.is_admin_approved(church_id)
);

-- [Inquiries]
CREATE POLICY "Manage own inquiries" ON inquiries FOR ALL TO authenticated USING (
    user_id = auth.uid() OR public.check_is_master()
) WITH CHECK (
    user_id = auth.uid() OR public.check_is_master()
);
-- Remove Admin view inquiries policy to make it master-only
DROP POLICY IF EXISTS "Admin view inquiries" ON inquiries;

-- [Inquiry Responses]
CREATE POLICY "View inquiry responses" ON inquiry_responses FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM inquiries i WHERE i.id = inquiry_responses.inquiry_id AND (i.user_id = auth.uid() OR public.check_is_master()))
);
CREATE POLICY "Manage inquiry responses" ON inquiry_responses FOR ALL TO authenticated USING (
    public.check_is_master()
);

-- [Interactions]
CREATE POLICY "View interactions" ON prayer_interactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Manage own interactions" ON prayer_interactions FOR ALL TO authenticated USING (auth.uid() = profile_id) WITH CHECK (auth.uid() = profile_id);

-- ============================================
-- STEP 8: 초기 데이터 및 마스터 설정
-- ============================================

INSERT INTO churches (id, name) VALUES ('00000000-0000-0000-0000-000000000001', 'Grace Church') ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
    target_uid UUID;
BEGIN
    SELECT id INTO target_uid FROM auth.users WHERE email = 'YOUR_MASTER_EMAIL@example.com';
    IF target_uid IS NOT NULL THEN
        INSERT INTO public.profiles (id, full_name, role, admin_status, is_master, is_onboarding_complete)
        VALUES (target_uid, '마스터 관리자', 'admin', 'approved', true, true)
        ON CONFLICT (id) DO UPDATE SET
        role = 'admin', is_master = true, admin_status = 'approved', is_onboarding_complete = true;
    END IF;
END $$;

NOTIFY pgrst, 'reload_schema';
-- Trigger to automatically unset is_linked when a profile is deleted (profile_id becomes NULL)
CREATE OR REPLACE FUNCTION public.handle_member_directory_unlinking()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.profile_id IS NULL THEN
    NEW.is_linked := false;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_member_profile_unlinked ON public.member_directory;
CREATE TRIGGER on_member_profile_unlinked
  BEFORE UPDATE OF profile_id ON public.member_directory
  FOR EACH ROW
  WHEN (OLD.profile_id IS NOT NULL AND NEW.profile_id IS NULL)
  EXECUTE FUNCTION public.handle_member_directory_unlinking();
