-- Phase 2C correction:
-- Deleting a department cascades groups/member_directory. End active memberships before
-- those cascades so Phase 2 does not retain active rows with deleted department context.

CREATE OR REPLACE FUNCTION public.phase2_sync_department_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memberships
  SET status = 'ended',
      ends_at = COALESCE(ends_at, now()),
      department_id = NULL,
      updated_at = now()
  WHERE department_id = OLD.id
    AND status = 'active';

  UPDATE public.profiles
  SET department_id = NULL
  WHERE department_id = OLD.id;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS phase2_department_delete_sync ON public.departments;
CREATE TRIGGER phase2_department_delete_sync
BEFORE DELETE ON public.departments
FOR EACH ROW EXECUTE FUNCTION public.phase2_sync_department_delete();
