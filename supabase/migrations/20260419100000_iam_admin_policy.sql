-- 교회 관리자(role='admin', admin_status='approved')가
-- 자신의 교회(church_id 일치) 인앱 메시지를 관리할 수 있도록 허용.
-- is_master 정책과 별도로 동작 (OR 조건).
CREATE POLICY "IAM church admin manage"
  ON public.in_app_messages FOR ALL TO authenticated
  USING (
    church_id IS NOT NULL
    AND church_id = (
      SELECT p.church_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
        AND p.admin_status = 'approved'
      LIMIT 1
    )
  )
  WITH CHECK (
    church_id IS NOT NULL
    AND church_id = (
      SELECT p.church_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
        AND p.admin_status = 'approved'
      LIMIT 1
    )
  );
