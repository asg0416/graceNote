-- 인앱 메시지 이미지 및 슬라이드 지원 추가

ALTER TABLE public.in_app_messages
    ADD COLUMN IF NOT EXISTS image_url text,
    ADD COLUMN IF NOT EXISTS slides    jsonb;

-- image_url schema validation
ALTER TABLE public.in_app_messages
    ADD CONSTRAINT iam_image_url_https
        CHECK (image_url IS NULL OR image_url ~* '^https?://');

-- Supabase Storage: 공개 버킷 생성
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'iam-images',
    'iam-images',
    true,
    5242880,  -- 5MB
    ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS
CREATE POLICY "iam_images_public_read"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'iam-images');

CREATE POLICY "iam_images_auth_insert"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'iam-images');

CREATE POLICY "iam_images_auth_delete"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'iam-images');
