-- supabase/migrations/20260415000000_no_meeting_days.sql

CREATE TABLE IF NOT EXISTS public.no_meeting_days (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  week_date     date NOT NULL,
  reason        text NOT NULL,
  created_by    uuid REFERENCES public.profiles(id),
  created_at    timestamptz DEFAULT now(),
  CONSTRAINT no_meeting_days_dept_week_unique UNIQUE (department_id, week_date)
);

ALTER TABLE public.no_meeting_days ENABLE ROW LEVEL SECURITY;

-- 읽기: 같은 부서 소속 유저 (profiles.department_id 기준)
CREATE POLICY "no_meeting_days_select"
  ON public.no_meeting_days
  FOR SELECT
  USING (
    department_id IN (
      SELECT department_id FROM public.profiles
      WHERE id = auth.uid() AND department_id IS NOT NULL
    )
  );

-- 쓰기(INSERT/UPDATE/DELETE): admin 또는 isMaster
CREATE POLICY "no_meeting_days_write"
  ON public.no_meeting_days
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND (role = 'admin' OR is_master = true)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND (role = 'admin' OR is_master = true)
    )
  );
