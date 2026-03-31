-- Create notification_dedup table with UNIQUE constraint for atomic dedup
-- Prevents race condition where concurrent trigger calls all pass SELECT check

CREATE TABLE IF NOT EXISTS public.notification_dedup (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id uuid NOT NULL,
  week_id uuid NOT NULL,
  event_type text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Core: UNIQUE constraint ensures only one INSERT succeeds for concurrent calls
ALTER TABLE public.notification_dedup
  ADD CONSTRAINT notification_dedup_unique
  UNIQUE (group_id, week_id, event_type);

-- RLS: Edge Function uses service_role_key, so no RLS needed
-- But disable RLS explicitly to be safe
ALTER TABLE public.notification_dedup ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on notification_dedup"
  ON public.notification_dedup
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
