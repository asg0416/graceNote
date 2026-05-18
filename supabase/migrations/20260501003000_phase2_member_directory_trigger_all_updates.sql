-- Phase 2C correction:
-- Ensure member_directory inserts also fire Phase 2 sync reliably.
-- The sync function does not update member_directory, so a broad UPDATE trigger
-- is safer than missing a membership-affecting column.

DROP TRIGGER IF EXISTS phase2_member_directory_sync ON public.member_directory;

CREATE TRIGGER phase2_member_directory_sync
AFTER INSERT OR UPDATE
ON public.member_directory
FOR EACH ROW EXECUTE FUNCTION public.phase2_sync_member_directory();

