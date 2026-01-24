-- Migration 13: Person ID Integration & Unified Member Management (Fixed Field Mismatch)

-- 1. Add person_id to member_directory and profiles
ALTER TABLE public.member_directory ADD COLUMN IF NOT EXISTS person_id UUID;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS person_id UUID;

-- 2. Create function to generate / find person_id
CREATE OR REPLACE FUNCTION public.get_or_create_person_id(p_full_name TEXT, p_phone TEXT)
RETURNS UUID AS $$
DECLARE
    v_person_id UUID;
BEGIN
    -- Find existing person_id with same name and phone from member_directory or profiles
    SELECT person_id INTO v_person_id 
    FROM public.member_directory 
    WHERE full_name = p_full_name AND phone = p_phone AND person_id IS NOT NULL
    LIMIT 1;

    IF v_person_id IS NULL THEN
        SELECT person_id INTO v_person_id 
        FROM public.profiles 
        WHERE full_name = p_full_name AND phone = p_phone AND person_id IS NOT NULL
        LIMIT 1;
    END IF;

    -- If not found, generate new UI
    IF v_person_id IS NULL THEN
        v_person_id := uuid_generate_v4();
    END IF;

    RETURN v_person_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Initialize person_id for existing records
UPDATE public.member_directory m1
SET person_id = (
    SELECT MIN(COALESCE(sub.person_id, uuid_generate_v4())::text)::uuid
    FROM public.member_directory sub
    WHERE sub.full_name = m1.full_name AND sub.phone = m1.phone
)
WHERE person_id IS NULL;

UPDATE public.profiles p
SET person_id = (
    SELECT person_id 
    FROM public.member_directory m 
    WHERE m.full_name = p.full_name AND m.phone = p.phone AND m.person_id IS NOT NULL 
    LIMIT 1
)
WHERE person_id IS NULL;

-- 4. Relax strict phone unique constraint
ALTER TABLE public.member_directory DROP CONSTRAINT IF EXISTS member_directory_phone_key;
UPDATE public.member_directory SET phone = '' WHERE phone IS NULL;
ALTER TABLE public.member_directory ALTER COLUMN phone SET NOT NULL;

-- 5. Trigger to sync data between records (Member Directory -> Others)
CREATE OR REPLACE FUNCTION public.sync_person_data()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent infinite loop
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- Sync to other records in member_directory (Fields that EXIST in member_directory)
    UPDATE public.member_directory
    SET 
        full_name = NEW.full_name,
        phone = NEW.phone,
        spouse_name = NEW.spouse_name,
        children_info = NEW.children_info,
        birth_date = NEW.birth_date,
        wedding_anniversary = NEW.wedding_anniversary,
        notes = NEW.notes,
        avatar_url = NEW.avatar_url,
        -- family_id is currently missing in member_directory in live DB
        profile_id = NEW.profile_id,
        is_linked = NEW.is_linked
    WHERE person_id = NEW.person_id AND id <> NEW.id;

    -- Also sync to profiles (Fields that EXIST in profiles)
    UPDATE public.profiles
    SET 
        full_name = NEW.full_name,
        phone = NEW.phone,
        avatar_url = NEW.avatar_url,
        wedding_anniversary = NEW.wedding_anniversary,
        children_info = NEW.children_info,
        notes = NEW.notes
        -- birth_date is missing in profiles
    WHERE person_id = NEW.person_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_member_data_update ON public.member_directory;
CREATE TRIGGER on_member_data_update
AFTER UPDATE OF full_name, phone, spouse_name, children_info, birth_date, wedding_anniversary, notes, avatar_url, profile_id, is_linked
ON public.member_directory
FOR EACH ROW
EXECUTE FUNCTION public.sync_person_data();

-- 6. Trigger to automatically assign person_id on insert
CREATE OR REPLACE FUNCTION public.handle_member_person_id_assignment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.person_id IS NULL THEN
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_member_insert_assign_person_id ON public.member_directory;
CREATE TRIGGER on_member_insert_assign_person_id
BEFORE INSERT ON public.member_directory
FOR EACH ROW
EXECUTE FUNCTION public.handle_member_person_id_assignment();

-- 7. Trigger to automatically assign person_id on update if it's currently null
DROP TRIGGER IF EXISTS on_member_update_assign_person_id ON public.member_directory;
CREATE TRIGGER on_member_update_assign_person_id
BEFORE UPDATE ON public.member_directory
FOR EACH ROW
WHEN (NEW.person_id IS NULL AND (NEW.full_name IS NOT NULL AND NEW.phone IS NOT NULL))
EXECUTE FUNCTION public.handle_member_person_id_assignment();

-- 8. Also handle profiles person_id assignment
CREATE OR REPLACE FUNCTION public.handle_profile_person_id_assignment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.person_id IS NULL THEN
        NEW.person_id := public.get_or_create_person_id(NEW.full_name, NEW.phone);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_profile_upsert_assign_person_id ON public.profiles;
CREATE TRIGGER on_profile_upsert_assign_person_id
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.handle_profile_person_id_assignment();

-- 9. Update check_phone_uniqueness to be smarter
CREATE OR REPLACE FUNCTION public.check_phone_uniqueness()
RETURNS TRIGGER AS $$
BEGIN
  -- Skip check if phone is NULL
  IF NEW.phone IS NULL OR NEW.phone = '' THEN
    RETURN NEW;
  END IF;

  -- Allow if the phone belongs to a profile that has the SAME person_id
  IF EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE phone = NEW.phone 
    AND (NEW.person_id IS NULL OR person_id <> NEW.person_id)
    AND (NEW.profile_id IS NULL OR id <> NEW.profile_id)
  ) THEN
    RAISE EXCEPTION '이미 가입된 계정에서 사용 중인 전화번호입니다. (phone_cross_uniqueness)';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. Profile to Member Directory Sync
CREATE OR REPLACE FUNCTION public.sync_profile_to_member()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent infinite loop
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- Sync to all matching member_directory records (Fields EXIST in member_directory)
    UPDATE public.member_directory
    SET 
        full_name = NEW.full_name,
        phone = NEW.phone,
        avatar_url = NEW.avatar_url,
        wedding_anniversary = NEW.wedding_anniversary,
        children_info = NEW.children_info,
        notes = NEW.notes
        -- birth_date missing in profiles NEW record
    WHERE person_id = NEW.person_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_profile_data_update ON public.profiles;
CREATE TRIGGER on_profile_data_update
AFTER UPDATE OF full_name, phone, avatar_url, wedding_anniversary, children_info, notes
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_profile_to_member();
