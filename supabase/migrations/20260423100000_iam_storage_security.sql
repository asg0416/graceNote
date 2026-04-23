-- supabase/migrations/20260423100000_iam_storage_security.sql
-- iam-images 스토리지 업로드 권한을 admin/master 전용으로 강화
-- (기존: 로그인된 모든 유저 → 변경: admin 또는 master만 허용)

DROP POLICY IF EXISTS "iam_images_auth_insert" ON storage.objects;

CREATE POLICY "iam_images_admin_insert"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'iam-images'
        AND EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
              AND (
                is_master = true
                OR (role = 'admin' AND admin_status = 'approved')
              )
        )
    );
