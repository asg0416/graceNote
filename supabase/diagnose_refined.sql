-- Refined Diagnostic: Find Missing vs Ghost Memberships (Set Difference)
-- This avoids "False Positives" for users with valid multi-group membership.

WITH 
-- 1. All valid memberships according to Admin Directory (The Truth)
directory_list AS (
  SELECT 
    profile_id, 
    group_name, 
    church_id, 
    full_name 
  FROM member_directory 
  WHERE profile_id IS NOT NULL
),

-- 2. All active memberships in the App/DB
actual_membership_list AS (
  SELECT 
    gm.profile_id, 
    g.name as group_name, 
    gm.role_in_group
  FROM group_members gm
  JOIN groups g ON gm.group_id = g.id
  WHERE gm.is_active = true
)

-- Result 1: "Ghost Memberships" 
-- Users in a group in the App, but NOT in that group in Admin Directory.
-- (This captures Lee Hae-bi's old "Jeongheon Jinseul Jo" entry)
SELECT 
  'GHOST (Exists in App, Missing in Admin)' as issue_type,
  a.full_name as user_name,
  a.group_name as wrong_group_in_app,
  '-' as correct_group_should_be
FROM (
  SELECT am.profile_id, am.group_name, p.full_name 
  FROM actual_membership_list am
  JOIN profiles p ON am.profile_id = p.id
) a
LEFT JOIN directory_list d 
  ON a.profile_id = d.profile_id AND a.group_name = d.group_name
WHERE d.profile_id IS NULL

UNION ALL

-- Result 2: "Missing Assignments"
-- Users in Admin Directory, but NOT in that group in the App.
-- (This captures Lee Hae-bi's missing "Hyoseok Haebi Jo" entry)
SELECT 
  'MISSING (Exists in Admin, Missing in App)' as issue_type,
  d.full_name as user_name,
  '-' as wrong_group_in_app,
  d.group_name as missing_group_in_app
FROM directory_list d
LEFT JOIN actual_membership_list a 
  ON d.profile_id = a.profile_id AND d.group_name = a.group_name
WHERE a.profile_id IS NULL

ORDER BY user_name, issue_type;
