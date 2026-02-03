-- Diagnostic Query: Check group mismatch for '이해비'
-- 1. Find profile ID by name
WITH target_user AS (
    SELECT id, full_name, person_id 
    FROM profiles 
    WHERE full_name = '이해비'
)
SELECT 
    'Profile' as source,
    u.full_name,
    u.id as profile_id, 
    u.person_id,
    '-' as group_name,
    '-' as role
FROM target_user u

UNION ALL

-- 2. Check Member Directory (What Admin sees + What should be)
SELECT 
    'Member Directory' as source,
    md.full_name,
    md.profile_id,
    md.person_id,
    md.group_name,
    '-' as role
FROM member_directory md
WHERE md.full_name = '이해비'

UNION ALL

-- 3. Check Group Members (What App sees)
SELECT 
    'Group Members Setup' as source,
    p.full_name,
    gm.profile_id,
    NULL as person_id,
    g.name as group_name,
    gm.role_in_group as role
FROM group_members gm
JOIN groups g ON gm.group_id = g.id
JOIN profiles p ON gm.profile_id = p.id
WHERE p.full_name = '이해비' AND gm.is_active = true;
