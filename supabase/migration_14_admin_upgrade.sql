-- Existing users who want to become admins need a way to 'upgrade' their profile
-- since they cannot use the SignUp flow (already registered).
-- This function allows an authenticated user to update their profile with admin-related fields
-- and set their status to 'pending'.

CREATE OR REPLACE FUNCTION public.submit_admin_request(
  p_full_name text,
  p_church_id uuid,
  p_department_id uuid,
  p_phone text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update the user's profile
  UPDATE public.profiles
  SET 
    full_name = p_full_name,
    church_id = p_church_id,
    department_id = p_department_id,
    phone = p_phone,
    role = 'admin',      -- Set role to admin so they are treated as an admin candidate
    admin_status = 'pending', -- Mark as pending approval
    updated_at = now()
  WHERE id = auth.uid();
END;
$$;
