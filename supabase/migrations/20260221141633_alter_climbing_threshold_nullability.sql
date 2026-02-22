-- 1. climbing_threshold의 DEFAULT 값을 제거하고 NULL을 허용하도록 변경
ALTER TABLE public.groups 
ALTER COLUMN climbing_threshold DROP DEFAULT,
ALTER COLUMN climbing_threshold DROP NOT NULL;

-- 2. 새가족 조가 아닌 경우 기존의 climbing_threshold를 NULL로 초기화
UPDATE public.groups 
SET climbing_threshold = NULL 
WHERE is_new_member_group = false;
