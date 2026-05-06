-- Phase 2C correction:
-- Phone identifiers are source-derived rows and must follow source phone updates.
-- Previous sync used ON CONFLICT DO NOTHING, leaving stale phone identifiers after edits.

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
  ON CONFLICT DO NOTHING;

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

  INSERT INTO public.member_profiles (
    person_id,
    profile_id,
    full_name,
    phone,
    avatar_url
  )
  SELECT
    v_person_id,
    NEW.id,
    NEW.full_name,
    NEW.phone,
    NEW.avatar_url
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.member_profiles mp
    WHERE mp.profile_id = NEW.id
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase2_sync_member_directory()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_person_id uuid;
  v_phone text;
  v_group_id uuid;
BEGIN
  IF NEW.church_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_person_id := public.phase2_upsert_person(
    NEW.church_id,
    NEW.person_id,
    NEW.profile_id,
    NEW.id,
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
  VALUES (v_person_id, 'legacy_directory', NEW.id::text, 'member_directory', NEW.id, false)
  ON CONFLICT DO NOTHING;

  IF v_phone IS NOT NULL THEN
    INSERT INTO public.person_identifiers (
      person_id,
      kind,
      value,
      source_table,
      source_id,
      is_primary
    )
    VALUES (v_person_id, 'phone', v_phone, 'member_directory', NEW.id, false)
    ON CONFLICT (kind, source_table, source_id)
      WHERE source_table IS NOT NULL AND source_id IS NOT NULL
    DO UPDATE SET
      person_id = EXCLUDED.person_id,
      value = EXCLUDED.value,
      is_primary = EXCLUDED.is_primary;
  ELSE
    DELETE FROM public.person_identifiers
    WHERE kind = 'phone'
      AND source_table = 'member_directory'
      AND source_id = NEW.id;
  END IF;

  INSERT INTO public.member_profiles (
    person_id,
    profile_id,
    member_directory_id,
    full_name,
    phone,
    avatar_url,
    family_name
  )
  VALUES (
    v_person_id,
    NEW.profile_id,
    NEW.id,
    NEW.full_name,
    NEW.phone,
    NEW.avatar_url,
    NEW.family_name
  )
  ON CONFLICT (member_directory_id) DO UPDATE SET
    person_id = EXCLUDED.person_id,
    profile_id = EXCLUDED.profile_id,
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    avatar_url = EXCLUDED.avatar_url,
    family_name = EXCLUDED.family_name,
    updated_at = now();

  SELECT id INTO v_group_id
  FROM public.groups
  WHERE church_id = NEW.church_id
    AND department_id = NEW.department_id
    AND name = NEW.group_name
  LIMIT 1;

  IF v_group_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.group_members gm
      WHERE gm.member_directory_id = NEW.id
        AND gm.is_active = true
    )
  THEN
    INSERT INTO public.memberships (
      person_id,
      church_id,
      department_id,
      group_id,
      role,
      status,
      starts_at,
      ends_at,
      legacy_member_directory_id
    )
    VALUES (
      v_person_id,
      NEW.church_id,
      NEW.department_id,
      v_group_id,
      CASE WHEN NEW.role_in_group = 'leader' THEN 'leader' ELSE 'member' END,
      CASE WHEN COALESCE(NEW.is_active, true) THEN 'active' ELSE 'inactive' END,
      COALESCE(NEW.joined_at, NEW.created_at, now()),
      CASE WHEN COALESCE(NEW.is_active, true) THEN NULL ELSE COALESCE(NEW.left_at, now()) END,
      NEW.id
    )
    ON CONFLICT (legacy_member_directory_id)
      WHERE legacy_group_member_id IS NULL AND legacy_member_directory_id IS NOT NULL
    DO UPDATE SET
      person_id = EXCLUDED.person_id,
      church_id = EXCLUDED.church_id,
      department_id = EXCLUDED.department_id,
      group_id = EXCLUDED.group_id,
      role = EXCLUDED.role,
      status = EXCLUDED.status,
      ends_at = EXCLUDED.ends_at,
      updated_at = now();
  ELSE
    UPDATE public.memberships
    SET status = 'ended',
        ends_at = COALESCE(ends_at, now()),
        updated_at = now()
    WHERE legacy_member_directory_id = NEW.id
      AND legacy_group_member_id IS NULL
      AND status = 'active';
  END IF;

  RETURN NEW;
END;
$$;
