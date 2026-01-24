-- Sync missing emails from auth.users to public.profiles
UPDATE public.profiles p
SET email = u.email
FROM auth.users u
WHERE p.id = u.id 
  AND (p.email IS NULL OR p.email = '') 
  AND u.email IS NOT NULL;
