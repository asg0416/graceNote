-- Migration: Enhance Groups and member regrouping logic

-- 1. Add is_active column to groups table
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- 2. RPC to regroup members atomically
CREATE OR REPLACE FUNCTION public.regroup_members(
    p_member_ids UUID[],
    p_target_group_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_group_name TEXT;
    v_dept_id UUID;
    v_church_id UUID;
BEGIN
    -- 1. Get group info if target_group_id is provided
    IF p_target_group_id IS NOT NULL THEN
        SELECT name, department_id, church_id INTO v_group_name, v_dept_id, v_church_id
        FROM public.groups
        WHERE id = p_target_group_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Group not found';
        END IF;
    ELSE
        -- If moving to unassigned, we assume the department and church stay the same as current
        -- (This might need current department context if p_member_ids are empty, but here we just set group_name to null)
        v_group_name := NULL;
    END IF;

    -- 2. Update member_directory
    UPDATE public.member_directory
    SET group_name = v_group_name
    WHERE id = ANY(p_member_ids);

    -- 3. Synchronize group_members (for users who have a profile linked)
    -- This ensures the app's group view is consistent
    IF p_target_group_id IS NOT NULL THEN
        -- Insert or update group membership
        -- Note: This logic assumes one person is in one group per department usually.
        -- For simplicity, we upsert.
        INSERT INTO public.group_members (profile_id, group_id, is_active)
        SELECT profile_id, p_target_group_id, true
        FROM public.member_directory
        WHERE id = ANY(p_member_ids) AND profile_id IS NOT NULL
        ON CONFLICT (group_id, profile_id) DO UPDATE SET is_active = true;
        
        -- Optional: Deactivate other memberships in the SAME department for these profiles
        -- To be truly robust, we should find old groups in the same department and deactivate them.
        UPDATE public.group_members gm
        SET is_active = false
        FROM public.groups g
        WHERE gm.group_id = g.id
        AND g.department_id = v_dept_id
        AND gm.group_id <> p_target_group_id
        AND gm.profile_id IN (
            SELECT profile_id FROM public.member_directory WHERE id = ANY(p_member_ids) AND profile_id IS NOT NULL
        );
    ELSE
        -- If moving to unassigned, deactivate memberships in the current department
        -- We need to know which department the members belong to. 
        -- Taking the department from the first member found.
        SELECT department_id INTO v_dept_id FROM public.member_directory WHERE id = p_member_ids[1] LIMIT 1;
        
        UPDATE public.group_members gm
        SET is_active = false
        FROM public.groups g
        WHERE gm.group_id = g.id
        AND g.department_id = v_dept_id
        AND gm.profile_id IN (
            SELECT profile_id FROM public.member_directory WHERE id = ANY(p_member_ids) AND profile_id IS NOT NULL
        );
    END IF;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
