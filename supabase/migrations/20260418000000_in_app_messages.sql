-- supabase/migrations/20260418000000_in_app_messages.sql

-- ──────────────────────────────────────────────
-- 1. TABLES
-- ──────────────────────────────────────────────

CREATE TABLE public.in_app_messages (
  id            uuid          DEFAULT gen_random_uuid() PRIMARY KEY,
  -- 노출 범위 (null = 서비스 전체)
  church_id     uuid          REFERENCES public.churches(id)     ON DELETE CASCADE,
  department_id uuid          REFERENCES public.departments(id)  ON DELETE SET NULL,
  -- 콘텐츠
  title         text          NOT NULL,
  body          text          NOT NULL,
  cta_label     text,
  cta_url       text,
  -- 타입
  type          text          NOT NULL DEFAULT 'announcement'
                              CHECK (type IN ('announcement', 'update', 'survey')),
  display_type  text          NOT NULL DEFAULT 'slide_up'
                              CHECK (display_type IN ('slide_up', 'modal')),
  target_role   text          NOT NULL DEFAULT 'all'
                              CHECK (target_role IN ('all', 'leader', 'member')),
  -- 스케줄
  starts_at     timestamptz   NOT NULL DEFAULT now(),
  expires_at    timestamptz,
  -- 상태
  is_active     boolean       NOT NULL DEFAULT true,
  is_deleted    boolean       NOT NULL DEFAULT false,
  priority      integer       NOT NULL DEFAULT 0,
  -- 메타
  created_by    uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    timestamptz   NOT NULL DEFAULT now(),
  updated_at    timestamptz   NOT NULL DEFAULT now(),
  -- 제약
  CONSTRAINT cta_url_https    CHECK (cta_url IS NULL OR cta_url ~ '^https?://'),
  CONSTRAINT expires_after_starts CHECK (expires_at IS NULL OR expires_at > starts_at)
);

CREATE TABLE public.iam_survey_responses (
  id          uuid      DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id  uuid      NOT NULL REFERENCES public.in_app_messages(id) ON DELETE CASCADE,
  user_id     uuid      NOT NULL REFERENCES public.profiles(id)         ON DELETE CASCADE,
  rating      integer   NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id)
);

-- ──────────────────────────────────────────────
-- 2. INDEXES
-- ──────────────────────────────────────────────

CREATE INDEX idx_iam_active_schedule
  ON public.in_app_messages (is_active, is_deleted, starts_at, priority DESC)
  WHERE is_deleted = false;

CREATE INDEX idx_iam_church
  ON public.in_app_messages (church_id)
  WHERE is_deleted = false;

CREATE INDEX idx_iam_dept
  ON public.in_app_messages (department_id)
  WHERE is_deleted = false;

CREATE INDEX idx_iam_survey_message
  ON public.iam_survey_responses (message_id);

CREATE INDEX idx_iam_survey_user
  ON public.iam_survey_responses (user_id);

-- ──────────────────────────────────────────────
-- 3. updated_at 자동 갱신 트리거
-- ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER iam_set_updated_at
  BEFORE UPDATE ON public.in_app_messages
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ──────────────────────────────────────────────
-- 4. RLS
-- ──────────────────────────────────────────────

ALTER TABLE public.in_app_messages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.iam_survey_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "iam_select_active"
  ON public.in_app_messages FOR SELECT TO authenticated
  USING (
    is_active   = true
    AND is_deleted = false
    AND now()   >= starts_at
    AND (expires_at IS NULL OR now() < expires_at)
    AND (church_id IS NULL
         OR church_id = public.get_my_church_id())
    AND (department_id IS NULL
         OR department_id = (
           SELECT department_id FROM public.profiles
           WHERE id = auth.uid() LIMIT 1
         ))
  );

CREATE POLICY "iam_master_all"
  ON public.in_app_messages FOR ALL TO authenticated
  USING      (public.check_is_master())
  WITH CHECK (public.check_is_master());

CREATE POLICY "survey_insert_own"
  ON public.iam_survey_responses FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "survey_select_own"
  ON public.iam_survey_responses FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "survey_master_select"
  ON public.iam_survey_responses FOR SELECT TO authenticated
  USING (public.check_is_master());

-- ──────────────────────────────────────────────
-- 5. Supabase Realtime 등록
-- ──────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE public.in_app_messages;
