-- Fix: Sync Trigger to update Group Members when Member Directory changes
-- Created at: 2026-02-03
-- Description: Automatically updates group_members table when a group is changed in member_directory.

CREATE OR REPLACE FUNCTION public.sync_directory_to_group_members()
RETURNS TRIGGER AS $$
DECLARE
  v_new_group_id UUID;
BEGIN
  -- 1. If profile_id is NULL, no need to sync to group_members (not a real user yet)
  IF NEW.profile_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 2. Check if group_name changed
  IF OLD.group_name IS DISTINCT FROM NEW.group_name OR NEW.profile_id IS DISTINCT FROM OLD.profile_id THEN
    
    -- Find the Group ID corresponding to the new group name (in the same church/dept)
    SELECT id INTO v_new_group_id
    FROM public.groups
    WHERE church_id = NEW.church_id
      AND department_id = NEW.department_id
      AND name = NEW.group_name
    LIMIT 1;

    IF v_new_group_id IS NOT NULL THEN
      -- A. Deactivate old membership
      UPDATE public.group_members
      SET is_active = false
      WHERE profile_id = NEW.profile_id 
        AND is_active = true;

      -- B. Insert or Reactivate new membership
      --    Check if record already exists (even if inactive) to prevent duplicates
      IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id = v_new_group_id AND profile_id = NEW.profile_id) THEN
          UPDATE public.group_members
          SET is_active = true,
              role_in_group = COALESCE(role_in_group, 'member'), -- Keep existing role if set, else member
              joined_at = NOW() -- Update join time to now
          WHERE group_id = v_new_group_id AND profile_id = NEW.profile_id;
      ELSE
          INSERT INTO public.group_members (group_id, profile_id, role_in_group, is_active, joined_at)
          VALUES (
            v_new_group_id, 
            NEW.profile_id, 
            'member', 
            true, 
            NOW()
          );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create Trigger
DROP TRIGGER IF EXISTS on_directory_group_change ON public.member_directory;
CREATE TRIGGER on_directory_group_change
  AFTER UPDATE OF group_name, profile_id
  ON public.member_directory
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_directory_to_group_members();
