-- Migration: Securely allow Group Leaders to manage their own Group Members using RPC
-- Created at: 2026-02-02
-- Description: Uses a SECURITY DEFINER function to prevent RLS recursion/deadlocks.

-- 1. Create a secure function to check permissions
CREATE OR REPLACE FUNCTION public.check_group_leader_permission(
  target_church_id UUID,
  target_department_id UUID,
  target_group_name TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
  -- A. Check if user is a Church Admin (Global Admin)
  -- Reusing existing helper if available, or manual check for safety
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND (
      (role = 'admin' AND admin_status = 'approved' AND church_id = target_church_id)
      OR is_master = true
    )
  ) THEN
    RETURN TRUE;
  END IF;

  -- B. Check if user is a Leader/Board of the specific group
  RETURN EXISTS (
    SELECT 1
    FROM public.group_members gm
    JOIN public.groups g ON gm.group_id = g.id
    WHERE gm.profile_id = auth.uid()
      AND gm.role_in_group IN ('leader', 'admin') -- Check role in group
      AND gm.is_active = true
      AND g.church_id = target_church_id
      AND g.department_id = target_department_id
      AND g.name = target_group_name -- String match on Group Name
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; -- Critical: Bypasses RLS on underlying tables during check

-- 2. Update the Policy on member_directory
DROP POLICY IF EXISTS "Admins manage directory" ON member_directory;
DROP POLICY IF EXISTS "Admins and Leaders manage directory" ON member_directory;
DROP POLICY IF EXISTS "Leaders manage directory" ON member_directory;

CREATE POLICY "Leaders manage directory" ON member_directory
FOR ALL TO authenticated
USING (
  public.check_group_leader_permission(church_id, department_id, group_name)
)
WITH CHECK (
  public.check_group_leader_permission(church_id, department_id, group_name)
);
