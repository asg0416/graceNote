-- Phase 2A correction:
-- One app profile can be linked to multiple directory/profile rows across memberships.
-- Keep member_directory_id unique, but make profile_id a non-unique lookup index.

ALTER TABLE public.member_profiles
  DROP CONSTRAINT IF EXISTS member_profiles_profile_id_key;

CREATE INDEX IF NOT EXISTS idx_member_profiles_profile_id
  ON public.member_profiles(profile_id)
  WHERE profile_id IS NOT NULL;
