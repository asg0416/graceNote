-- Phase 2C correction:
-- Profile identifiers and profile-only member_profiles must follow profile updates.
-- Onboarding can change profiles.person_id from a temporary profile person to an existing
-- directory person. Source-derived auth_user/legacy_profile identifiers must move with it.

CREATE OR REPLACE FUNCTION public.phase2_sync_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_person_id uuid;
  v_phone text;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  IF NEW.church_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_person_id := public.phase2_upsert_person(
    NEW.church_id,
    NEW.person_id,
    NEW.id,
    NULL,
    NEW.full_name,
    NEW.phone
  );
  v_phone := public.phase2_normalize_phone(NEW.phone);

  INSERT INTO public.person_identifiers (
    person_id,
    kind,
    value,
    source_table,
    source_id,
    is_primary
  )
  VALUES
    (v_person_id, 'legacy_profile', NEW.id::text, 'profiles', NEW.id, false),
    (v_person_id, 'auth_user', NEW.id::text, 'profiles', NEW.id, true)
  ON CONFLICT (kind, source_table, source_id)
    WHERE source_table IS NOT NULL AND source_id IS NOT NULL
  DO UPDATE SET
    person_id = EXCLUDED.person_id,
    value = EXCLUDED.value,
    is_primary = EXCLUDED.is_primary;

  IF v_phone IS NOT NULL THEN
    INSERT INTO public.person_identifiers (
      person_id,
      kind,
      value,
      source_table,
      source_id,
      is_primary
    )
    VALUES (v_person_id, 'phone', v_phone, 'profiles', NEW.id, false)
    ON CONFLICT (kind, source_table, source_id)
      WHERE source_table IS NOT NULL AND source_id IS NOT NULL
    DO UPDATE SET
      person_id = EXCLUDED.person_id,
      value = EXCLUDED.value,
      is_primary = EXCLUDED.is_primary;
  ELSE
    DELETE FROM public.person_identifiers
    WHERE kind = 'phone'
      AND source_table = 'profiles'
      AND source_id = NEW.id;
  END IF;

  UPDATE public.member_profiles
  SET person_id = v_person_id,
      full_name = NEW.full_name,
      phone = NEW.phone,
      avatar_url = NEW.avatar_url,
      updated_at = now()
  WHERE profile_id = NEW.id
    AND member_directory_id IS NULL;

  IF NOT FOUND THEN
    INSERT INTO public.member_profiles (
      person_id,
      profile_id,
      full_name,
      phone,
      avatar_url
    )
    VALUES (
      v_person_id,
      NEW.id,
      NEW.full_name,
      NEW.phone,
      NEW.avatar_url
    );
  END IF;

  RETURN NEW;
END;
$$;
