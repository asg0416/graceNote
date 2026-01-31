-- person_id 불일치 성도 데이터 통합 및 클린업 스크립트
-- 1. profiles 테이블의 person_id를 기준으로 member_directory와 group_members를 일치시킵니다.

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        WITH sanitized_profiles AS (
            SELECT 
                regexp_replace(phone, '[^0-9]', '', 'g') as sanitized_phone,
                person_id
            FROM public.profiles
            WHERE phone IS NOT NULL AND phone <> ''
        ),
        sanitized_member_directory AS (
            SELECT 
                regexp_replace(phone, '[^0-9]', '', 'g') as sanitized_phone,
                person_id
            FROM public.member_directory
            WHERE phone IS NOT NULL AND phone <> ''
        )
        SELECT 
            p.person_id as correct_person_id,
            m.person_id as wrong_person_id
        FROM sanitized_profiles p
        JOIN sanitized_member_directory m ON p.sanitized_phone = m.sanitized_phone
        WHERE p.person_id <> m.person_id
    LOOP
        -- member_directory 업데이트
        UPDATE public.member_directory
        SET person_id = r.correct_person_id
        WHERE person_id = r.wrong_person_id;
        
        -- 관련 테이블이 더 있다면 (예: group_members 등) 여기서 추가 업데이트 가능
        -- 현재 스키마상 group_members에는 person_id가 없으나 만약 존재한다면 업데이트 필요
    END LOOP;
END $$;
