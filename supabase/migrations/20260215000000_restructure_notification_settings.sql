-- Create department_settings table
CREATE TABLE IF NOT EXISTS public.department_settings (
    department_id uuid PRIMARY KEY REFERENCES public.departments(id) ON DELETE CASCADE,
    leader_reminder_enabled boolean DEFAULT true,
    leader_reminder_days integer[] DEFAULT '{0,1,3,6}'::integer[],
    leader_reminder_time time without time zone DEFAULT '22:00:00'::time without time zone,
    climbing_alert_enabled boolean DEFAULT true,
    climbing_alert_day integer DEFAULT 5,
    climbing_alert_time time without time zone DEFAULT '20:00:00'::time without time zone,
    updated_at timestamp with time zone DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.department_settings ENABLE ROW LEVEL SECURITY;

-- Add RLS Policies
-- Select policy: Masters can see all, admins/members can see their own department's settings
CREATE POLICY "Users can view their department settings" ON public.department_settings
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
            AND (
                p.is_master = true 
                OR p.department_id = department_settings.department_id
                OR (p.role = 'admin' AND p.church_id = (SELECT church_id FROM public.departments WHERE id = department_settings.department_id))
            )
        )
    );

-- Update policy: Masters/Admins of the church can update
CREATE POLICY "Admins can manage their department settings" ON public.department_settings
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
            AND (
                p.is_master = true 
                OR (p.role = 'admin' AND p.church_id = (SELECT church_id FROM public.departments WHERE id = department_settings.department_id))
            )
        )
    );

-- Migrate data from church_settings to department_settings
-- For each church_setting, insert a department_setting for every department in that church
INSERT INTO public.department_settings (
    department_id,
    leader_reminder_enabled,
    leader_reminder_days,
    leader_reminder_time,
    climbing_alert_enabled,
    climbing_alert_day,
    climbing_alert_time,
    updated_at
)
SELECT 
    d.id,
    cs.leader_reminder_enabled,
    cs.leader_reminder_days,
    cs.leader_reminder_time,
    cs.climbing_alert_enabled,
    cs.climbing_alert_day,
    cs.climbing_alert_time,
    cs.updated_at
FROM public.church_settings cs
JOIN public.departments d ON d.church_id = cs.church_id
ON CONFLICT (department_id) DO NOTHING;

-- We will drop church_settings after verifying the migration
