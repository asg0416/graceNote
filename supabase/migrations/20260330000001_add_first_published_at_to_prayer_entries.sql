-- Add first_published_at to prayer_entries for distinguishing first publish vs re-publish
ALTER TABLE public.prayer_entries
ADD COLUMN IF NOT EXISTS first_published_at timestamptz DEFAULT NULL;

-- Backfill: mark all currently published entries as already published
UPDATE public.prayer_entries
SET first_published_at = created_at
WHERE status = 'published' AND first_published_at IS NULL;

-- Auto-set first_published_at on first publish via trigger
CREATE OR REPLACE FUNCTION public.set_first_published_at()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'published' AND NEW.first_published_at IS NULL THEN
    NEW.first_published_at = NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_first_published_at ON public.prayer_entries;
CREATE TRIGGER trg_set_first_published_at
  BEFORE INSERT OR UPDATE ON public.prayer_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.set_first_published_at();

-- App config table for environment-specific settings (e.g. Edge Function URL).
-- Each environment stores its own base URL, so this migration works for both dev and prod.
CREATE TABLE IF NOT EXISTS public.app_config (
  key text PRIMARY KEY,
  value text NOT NULL
);

-- Fix notify_on_event() to include old_record for UPDATE detection.
-- Reads Edge Function URL from app_config instead of hardcoding.
CREATE OR REPLACE FUNCTION public.notify_on_event()
RETURNS TRIGGER AS $$
DECLARE
  _payload jsonb;
  _url text;
BEGIN
  SELECT value INTO _url FROM public.app_config WHERE key = 'edge_function_base_url';
  IF _url IS NULL THEN
    RAISE WARNING 'edge_function_base_url not configured in app_config';
    RETURN NEW;
  END IF;

  _payload := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'record', row_to_json(NEW)::jsonb,
    'schema', TG_TABLE_SCHEMA,
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD)::jsonb ELSE NULL END
  );

  PERFORM net.http_post(
    url := _url || '/notify-event',
    body := _payload
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Push notification trigger failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
