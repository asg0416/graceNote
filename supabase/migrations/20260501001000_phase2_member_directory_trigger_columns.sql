-- Phase 2C correction:
-- member_directory changes that affect directory-only memberships must fire
-- the Phase 2 sync trigger.

DROP TRIGGER IF EXISTS phase2_member_directory_sync ON public.member_directory;

CREATE TRIGGER phase2_member_directory_sync
AFTER INSERT OR UPDATE OF
  church_id,
  department_id,
  full_name,
  phone,
  profile_id,
  person_id,
  family_name,
  avatar_url,
  group_name,
  role_in_group,
  is_active,
  joined_at,
  left_at
ON public.member_directory
FOR EACH ROW EXECUTE FUNCTION public.phase2_sync_member_directory();

