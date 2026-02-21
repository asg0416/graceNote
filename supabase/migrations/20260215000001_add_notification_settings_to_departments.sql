ALTER TABLE public.departments
ADD COLUMN IF NOT EXISTS leader_reminder_enabled boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS leader_reminder_days integer[] DEFAULT '{0,1,3,6}'::integer[],
ADD COLUMN IF NOT EXISTS leader_reminder_time time without time zone DEFAULT '22:00:00'::time without time zone,
ADD COLUMN IF NOT EXISTS climbing_alert_enabled boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS climbing_alert_day integer DEFAULT 5,
ADD COLUMN IF NOT EXISTS climbing_alert_time time without time zone DEFAULT '20:00:00'::time without time zone;
