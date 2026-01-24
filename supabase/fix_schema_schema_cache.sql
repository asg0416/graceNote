-- [GraceNote Fix SQL] - V10.1 (RLS 및 누락 컬럼 통합 해결)

-- 1. member_directory 테이블 필수 컬럼 및 타입 강제 재설정
DO $$
BEGIN
    -- birth_date
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_directory' AND column_name='birth_date') THEN
        ALTER TABLE public.member_directory ADD COLUMN birth_date DATE;
    END IF;

    -- wedding_anniversary
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_directory' AND column_name='wedding_anniversary') THEN
        ALTER TABLE public.member_directory ADD COLUMN wedding_anniversary DATE;
    END IF;

    -- spouse_name
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_directory' AND column_name='spouse_name') THEN
        ALTER TABLE public.member_directory ADD COLUMN spouse_name TEXT;
    END IF;

    -- children_info
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_directory' AND column_name='children_info') THEN
        ALTER TABLE public.member_directory ADD COLUMN children_info TEXT;
    END IF;

    -- notes
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_directory' AND column_name='notes') THEN
        ALTER TABLE public.member_directory ADD COLUMN notes TEXT;
    END IF;
END $$;

-- 2. prayer_entries 테이블 together_count 컬럼 확인 및 추가
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prayer_entries' AND column_name='together_count') THEN
        ALTER TABLE public.prayer_entries ADD COLUMN together_count INTEGER DEFAULT 0;
    END IF;
END $$;

-- 3. RLS 정책 업데이트 (조장 권한 허용)
-- 기존 정책 삭제 후 재등록
DROP POLICY IF EXISTS "Admins manage directory" ON member_directory;
DROP POLICY IF EXISTS "Admins and Leaders manage directory" ON member_directory;

CREATE POLICY "Admins and Leaders manage directory" ON member_directory 
FOR ALL TO authenticated 
USING (public.is_admin_approved(church_id) OR public.is_leader(church_id)) 
WITH CHECK (public.is_admin_approved(church_id) OR public.is_leader(church_id));

-- 4. PostgREST 스키마 캐시 강제 새로고침
NOTIFY pgrst, 'reload schema';

-- 5. 최종 확인 쿼리
SELECT table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name IN ('member_directory', 'prayer_entries') 
AND column_name IN ('birth_date', 'wedding_anniversary', 'spouse_name', 'children_info', 'notes', 'together_count')
ORDER BY table_name, column_name;
