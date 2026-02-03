-- Investigation Query: Find inconsistencies between Member Directory and Group Members
-- 1. Members with mismatched group assignment (Directory vs Actual Group Membership)
--    Only considers members who are linked to a profile.
WITH mismatched_users AS (
    SELECT 
        md.full_name,
        md.profile_id,
        md.group_name as directory_group,
        g.name as actual_group_name,
        gm.role_in_group
    FROM member_directory md
    JOIN group_members gm ON md.profile_id = gm.profile_id
    JOIN groups g ON gm.group_id = g.id
    WHERE md.profile_id IS NOT NULL 
    AND gm.is_active = true
    AND md.group_name != g.name
),

-- 2. Members present in Directory (with profile) but missing from Group Members table entirely
missing_group_members AS (
    SELECT 
        md.full_name,
        md.profile_id,
        md.group_name as directory_group
    FROM member_directory md
    WHERE md.profile_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM group_members gm 
        WHERE gm.profile_id = md.profile_id AND gm.is_active = true
    )
),

-- 3. Duplicate profiles (Same Name + Same Phone Number part)
--    Helps identify if a user signed up twice.
duplicate_profiles AS (
    SELECT 
        p1.full_name,
        p1.phone,
        COUNT(*) as count
    FROM profiles p1
    WHERE p1.full_name IS NOT NULL
    GROUP BY p1.full_name, p1.phone
    HAVING COUNT(*) > 1
)

SELECT '1. Mismatched Groups' as issue_type, full_name, profile_id::text, directory_group, actual_group_name as extra_info 
FROM mismatched_users
UNION ALL
SELECT '2. Missing from Group Members', full_name, profile_id::text, directory_group, 'No active group_member record'
FROM missing_group_members
UNION ALL
SELECT '3. Duplicate Profiles', full_name, '-', phone, 'Count: ' || count::text
FROM duplicate_profiles;
