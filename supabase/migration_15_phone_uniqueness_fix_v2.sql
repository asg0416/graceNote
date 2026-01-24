-- Migration to fix duplicate phone numbers and enforce uniqueness

-- 1. Identify and handle existing duplicate phone numbers
-- We will keep the phone number for the most "valuable" profile and set others to NULL.
-- Priority: 'approved' > 'pending' > 'rejected' > 'none'
-- If same status, keep the most recently created one.

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT phone, id
        FROM (
            SELECT 
                phone, 
                id,
                ROW_NUMBER() OVER (
                    PARTITION BY phone 
                    ORDER BY 
                        CASE admin_status 
                            WHEN 'approved' THEN 1 
                            WHEN 'pending' THEN 2 
                            WHEN 'rejected' THEN 3 
                            ELSE 4 
                        END,
                        created_at DESC
                ) as rank
            FROM public.profiles
            WHERE phone IS NOT NULL AND phone <> ''
        ) t
        WHERE rank > 1
    ) LOOP
        UPDATE public.profiles SET phone = NULL WHERE id = r.id;
    END LOOP;
END $$;

-- 2. Now that duplicates are moved to NULL, apply the UNIQUE constraint
ALTER TABLE public.profiles ADD CONSTRAINT unique_phone UNIQUE (phone);

-- 3. Create/Update the secure RPC to check for existing phone numbers
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

-- 4. Grant access to the public (anon) and authenticated users
GRANT EXECUTE ON FUNCTION public.check_phone_exists(TEXT) TO anon, authenticated;
