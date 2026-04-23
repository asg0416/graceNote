-- supabase/migrations/20260423000000_iam_image_only.sql

-- image_only: 제목·본문을 DB에는 저장하되 앱에서 이미지+버튼만 표시
ALTER TABLE public.in_app_messages
  ADD COLUMN IF NOT EXISTS image_only boolean NOT NULL DEFAULT false;
