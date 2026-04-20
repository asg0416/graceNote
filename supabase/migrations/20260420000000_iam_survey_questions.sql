-- supabase/migrations/20260420000000_iam_survey_questions.sql

-- 1. in_app_messages에 survey_questions 컬럼 추가
ALTER TABLE public.in_app_messages
  ADD COLUMN IF NOT EXISTS survey_questions jsonb;

-- 2. iam_survey_responses: rating/comment 제거, answers 추가
ALTER TABLE public.iam_survey_responses
  DROP COLUMN IF EXISTS rating,
  DROP COLUMN IF EXISTS comment,
  ADD COLUMN IF NOT EXISTS answers jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.iam_survey_responses
  ADD CONSTRAINT answers_is_array CHECK (jsonb_typeof(answers) = 'array');
