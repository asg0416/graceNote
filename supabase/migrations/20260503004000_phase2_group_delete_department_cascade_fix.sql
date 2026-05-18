-- Phase 2C correction:
-- When a group is deleted as part of department cascade, do not update member_directory
-- rows that are being deleted by the same cascade. That can violate the department FK.

CREATE OR REPLACE FUNCTION public.phase2_sync_group_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_department_still_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.departments
    WHERE id = OLD.department_id
  )
  INTO v_department_still_exists;

  UPDATE public.memberships
  SET status = 'ended',
      ends_at = COALESCE(ends_at, now()),
      updated_at = now()
  WHERE group_id = OLD.id
    AND status = 'active';

  IF v_department_still_exists THEN
    UPDATE public.member_directory
    SET group_name = NULL
    WHERE church_id = OLD.church_id
      AND department_id = OLD.department_id
      AND group_name = OLD.name
      AND is_active = true;
  END IF;

  RETURN OLD;
END;
$$;
