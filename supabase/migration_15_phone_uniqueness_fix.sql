-- Migration to fix registration bypassing and redundant registrations

-- 1. Add unique constraint on phone number in profiles
ALTER TABLE public.profiles ADD CONSTRAINT unique_phone UNIQUE (phone);

-- 2. Create a secure RPC to check for existing phone numbers
-- This uses SECURITY DEFINER to bypass RLS, allowing registration form (unauthenticated) 
-- to safely check for duplicates without exposing the entire profiles table.
CREATE OR REPLACE FUNCTION public.check_phone_exists(p_phone TEXT)
RETURNS TABLE (
    p_exists BOOLEAN,
    p_full_name TEXT,
    p_email TEXT
) SECURITY DEFINER 
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        TRUE,
        full_name,
        email
    FROM public.profiles
    WHERE phone = p_phone
    LIMIT 1;
    
    -- If no rows found, return false
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::TEXT, NULL::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Grant access to the public (anon) and authenticated users
GRANT EXECUTE ON FUNCTION public.check_phone_exists(TEXT) TO anon, authenticated;
