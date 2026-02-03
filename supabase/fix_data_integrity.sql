-- DATA REPAIR SCRIPT
-- 1. Fix Group Mismatches (Lee Hae-bi, Yang Hyo-seok, Kim Shin-young)
-- 2. Fix Duplicate Profile Identity (Im Jin-seul vs Min Jae-hong)

DO $$
DECLARE
    -- IDs from your investigation
    v_haebi_id UUID := '8a270e46-d5a5-48d5-8ada-e1bec4fcc20a';
    v_hyoseok_id UUID := '29a3aa8d-ccbe-42a5-b99f-d9a7f47948af';
    v_shinyoung_id UUID := '1bc67a15-7948-4345-af9f-a0fa95cab622';
    
    v_duplicate_profile_id UUID := 'd6310dbe-9d89-4f7f-a4f3-51b81b465652';
    
    v_target_group_id UUID;
    v_wrong_group_id UUID;
    v_profile_name TEXT;
BEGIN
    -- ==========================================================
    -- PART 1: FIX GROUP MISMATCHES (Hyoseok Haebi Jo)
    -- ==========================================================
    
    -- 1. Get correct group ID for "효석 해비 조"
    --    (Assumes they are in the same church/department as their Member Directory entry)
    --    We simply lookup by name since it's unique enough within their context usually.
    SELECT id INTO v_target_group_id FROM public.groups WHERE name = '효석 해비 조' LIMIT 1;
    
    -- 2. Get wrong group ID for "정헌 진슬 조"
    SELECT id INTO v_wrong_group_id FROM public.groups WHERE name = '정헌 진슬 조' LIMIT 1;

    IF v_target_group_id IS NOT NULL THEN
        -- A. Lee Hae-bi
        -- Remove from wrong group
        DELETE FROM public.group_members 
        WHERE profile_id = v_haebi_id AND group_id = v_wrong_group_id;
        
        -- Insert into correct group (Check existence first)
        IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id = v_target_group_id AND profile_id = v_haebi_id) THEN
            UPDATE public.group_members SET is_active = true, role_in_group = 'leader'
            WHERE group_id = v_target_group_id AND profile_id = v_haebi_id;
        ELSE
            INSERT INTO public.group_members (group_id, profile_id, role_in_group, is_active, joined_at)
            VALUES (v_target_group_id, v_haebi_id, 'leader', true, NOW());
        END IF;

        -- B. Yang Hyo-seok
        -- Remove from wrong group
        DELETE FROM public.group_members 
        WHERE profile_id = v_hyoseok_id AND group_id = v_wrong_group_id;
        
        -- Insert into correct group
        IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id = v_target_group_id AND profile_id = v_hyoseok_id) THEN
            UPDATE public.group_members SET is_active = true, role_in_group = 'leader'
            WHERE group_id = v_target_group_id AND profile_id = v_hyoseok_id;
        ELSE
            INSERT INTO public.group_members (group_id, profile_id, role_in_group, is_active, joined_at)
            VALUES (v_target_group_id, v_hyoseok_id, 'leader', true, NOW());
        END IF;

        -- C. Kim Shin-young
        -- Insert into correct group
        IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id = v_target_group_id AND profile_id = v_shinyoung_id) THEN
            UPDATE public.group_members SET is_active = true
            WHERE group_id = v_target_group_id AND profile_id = v_shinyoung_id;
        ELSE
            INSERT INTO public.group_members (group_id, profile_id, role_in_group, is_active, joined_at)
            VALUES (v_target_group_id, v_shinyoung_id, 'member', true, NOW());
        END IF;
    END IF;

    -- ==========================================================
    -- PART 2: FIX DUPLICATE PROFILE ID (Im Jin-seul vs Min Jae-hong)
    -- ==========================================================
    
    -- Check who actually owns the profile
    SELECT full_name INTO v_profile_name FROM public.profiles WHERE id = v_duplicate_profile_id;

    IF v_profile_name IS NOT NULL THEN
        -- If profile name is '임진슬', unlink '민재홍'
        -- If profile name is '민재홍', unlink '임진슬'
        UPDATE public.member_directory
        SET profile_id = NULL,
            is_linked = false
        WHERE profile_id = v_duplicate_profile_id
        AND full_name != v_profile_name; -- Unlink the mismatched person
    END IF;

END $$;
