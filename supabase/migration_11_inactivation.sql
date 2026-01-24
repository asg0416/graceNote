-- 1. member_directory 테이블에 is_active 컬럼 추가
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_directory' AND column_name='is_active') THEN
        ALTER TABLE public.member_directory ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;
END $$;

-- 2. PostgREST 스키마 캐시 강제 새로고침
NOTIFY pgrst, 'reload schema';

-- 3. 확인용 쿼리
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'member_directory' 
AND column_name = 'is_active';
