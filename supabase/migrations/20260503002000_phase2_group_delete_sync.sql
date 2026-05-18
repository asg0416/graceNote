-- Phase 2C correction:
-- Deleting a group must not leave active memberships with group_id NULL or
-- active member_directory rows that still contain the deleted group name.

CREATE OR REPLACE FUNCTION public.phase2_sync_group_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memberships
  SET status = 'ended',
      ends_at = COALESCE(ends_at, now()),
      updated_at = now()
  WHERE group_id = OLD.id
    AND status = 'active';

  UPDATE public.member_directory
  SET group_name = NULL
  WHERE church_id = OLD.church_id
    AND department_id = OLD.department_id
    AND group_name = OLD.name
    AND is_active = true;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS phase2_group_delete_sync ON public.groups;
CREATE TRIGGER phase2_group_delete_sync
BEFORE DELETE ON public.groups
FOR EACH ROW EXECUTE FUNCTION public.phase2_sync_group_delete();
