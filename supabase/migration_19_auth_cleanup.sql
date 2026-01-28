-- Migration 19: Auth Cleanup
-- This migration adds functions to clean up "zombie" accounts that fail to complete onboarding.

-- 1. Function for a user to delete their own incomplete account
-- Used when a user is blocked by phone duplication and wants to start over with their original account.
CREATE OR REPLACE FUNCTION public.delete_self_in_onboarding()
RETURNS VOID AS $$
BEGIN
  -- Security check: ONLY allow deletion if onboarding is NOT complete
  IF EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND is_onboarding_complete = false
  ) THEN
    -- auth.users delete requires bypass via SECURITY DEFINER
    DELETE FROM auth.users WHERE id = auth.uid();
  ELSE
    RAISE EXCEPTION 'Only incomplete accounts can be self-deleted via this endpoint.';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = auth, public;

-- Allow authenticated users to call this
GRANT EXECUTE ON FUNCTION public.delete_self_in_onboarding() TO authenticated;

-- 2. Background cleanup function for older orphaned accounts
-- Deletes users who haven't completed onboarding for more than 24 hours.
CREATE OR REPLACE FUNCTION public.cleanup_orphaned_users()
RETURNS INT AS $$
DECLARE
  deleted_count INT;
BEGIN
  WITH targets AS (
    SELECT id FROM public.profiles 
    WHERE is_onboarding_complete = false 
    AND created_at < (NOW() - INTERVAL '24 hours')
    -- Prevent master accounts from accidental deletion even if flag is false
    AND is_master = false
  )
  DELETE FROM auth.users 
  WHERE id IN (SELECT id FROM targets);
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = auth, public;

-- Grant execute to authenticated (if manual trigger needed) and service_role
GRANT EXECUTE ON FUNCTION public.cleanup_orphaned_users() TO service_role;

COMMENT ON FUNCTION public.delete_self_in_onboarding() IS 'Allows a user to prune their own account if they are stuck in the onboarding phase.';
COMMENT ON FUNCTION public.cleanup_orphaned_users() IS 'Cleans up accounts that have been in onboarding for more than 24 hours.';
