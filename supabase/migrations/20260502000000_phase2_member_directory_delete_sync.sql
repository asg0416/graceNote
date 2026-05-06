-- Phase 2C safety fix:
-- When a legacy member_directory row is deleted, end derived Phase 2 memberships
-- before FK ON DELETE SET NULL removes the legacy_member_directory_id reference.
--
-- This specifically protects regrouping duplicate-card cleanup paths where the
-- UI deletes a redundant copied member_directory row after the same person still
-- exists in another group.

CREATE OR REPLACE FUNCTION public.phase2_end_memberships_on_member_directory_delete()
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
  WHERE legacy_member_directory_id = OLD.id
    AND status = 'active';

  DELETE FROM public.member_profiles
  WHERE member_directory_id = OLD.id;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS phase2_member_directory_delete_sync ON public.member_directory;
CREATE TRIGGER phase2_member_directory_delete_sync
BEFORE DELETE ON public.member_directory
FOR EACH ROW EXECUTE FUNCTION public.phase2_end_memberships_on_member_directory_delete();
