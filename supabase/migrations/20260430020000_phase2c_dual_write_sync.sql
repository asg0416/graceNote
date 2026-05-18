-- Phase 2C dual-write sync:
-- Keep additive Phase 2 tables in sync while legacy tables remain authoritative.

CREATE OR REPLACE FUNCTION public.phase2_normalize_phone(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g'), '')
$$;

CREATE OR REPLACE FUNCTION public.phase2_upsert_person(
  p_church_id uuid,
  p_existing_person_id uuid,
  p_profile_id uuid,
  p_member_directory_id uuid,
  p_display_name text,
  p_phone text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_person_id uuid;
  v_person_id uuid;
  v_normalized_phone text;
BEGIN
  IF p_church_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_profile_id IS NOT NULL THEN
    SELECT person_id INTO v_profile_person_id
    FROM public.profiles
    WHERE id = p_profile_id;
  END IF;

  v_person_id := COALESCE(
    p_existing_person_id,
    v_profile_person_id,
    p_profile_id,
    p_member_directory_id,
    gen_random_uuid()
  );
  v_normalized_phone := public.phase2_normalize_phone(p_phone);

  INSERT INTO public.people (
    id,
    church_id,
    display_name,
    normalized_phone,
    primary_profile_id
  )
  VALUES (
    v_person_id,
    p_church_id,
    COALESCE(NULLIF(p_display_name, ''), '[unknown]'),
    v_normalized_phone,
    p_profile_id
  )
  ON CONFLICT (id) DO UPDATE SET
    church_id = EXCLUDED.church_id,
    display_name = COALESCE(NULLIF(EXCLUDED.display_name, ''), public.people.display_name),
    normalized_phone = COALESCE(EXCLUDED.normalized_phone, public.people.normalized_phone),
    primary_profile_id = COALESCE(EXCLUDED.primary_profile_id, public.people.primary_profile_id),
    updated_at = now();

  RETURN v_person_id;
END;
$$;

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
    ON CONFLICT DO NOTHING;
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
    ON CONFLICT DO NOTHING;
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

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase2_sync_group_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group record;
  v_directory record;
  v_person_id uuid;
  v_profile_person_id uuid;
  v_profile_full_name text;
  v_profile_phone text;
  v_display_name text;
  v_legacy_member_directory_id uuid;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  SELECT id, church_id, department_id
  INTO v_group
  FROM public.groups
  WHERE id = NEW.group_id;

  IF v_group.id IS NULL OR v_group.church_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.member_directory_id IS NOT NULL THEN
    SELECT *
    INTO v_directory
    FROM public.member_directory
    WHERE id = NEW.member_directory_id;
  END IF;

  IF NEW.profile_id IS NOT NULL THEN
    SELECT person_id, full_name, phone
    INTO v_profile_person_id, v_profile_full_name, v_profile_phone
    FROM public.profiles
    WHERE id = NEW.profile_id;
  END IF;

  v_display_name := COALESCE(
    v_directory.full_name,
    v_profile_full_name,
    '[legacy missing member_directory]'
  );
  v_legacy_member_directory_id := v_directory.id;

  v_person_id := public.phase2_upsert_person(
    v_group.church_id,
    COALESCE(v_directory.person_id, v_profile_person_id),
    NEW.profile_id,
    NEW.member_directory_id,
    v_display_name,
    COALESCE(v_directory.phone, v_profile_phone)
  );

  INSERT INTO public.memberships (
    person_id,
    church_id,
    department_id,
    group_id,
    role,
    status,
    starts_at,
    ends_at,
    legacy_group_member_id,
    legacy_member_directory_id
  )
  VALUES (
    v_person_id,
    v_group.church_id,
    v_group.department_id,
    NEW.group_id,
    CASE WHEN NEW.role_in_group = 'leader' THEN 'leader' ELSE 'member' END,
    CASE WHEN COALESCE(NEW.is_active, true) THEN 'active' ELSE 'inactive' END,
    COALESCE(NEW.joined_at, now()),
    CASE WHEN COALESCE(NEW.is_active, true) THEN NULL ELSE now() END,
    NEW.id,
    v_legacy_member_directory_id
  )
  ON CONFLICT (legacy_group_member_id) DO UPDATE SET
    person_id = EXCLUDED.person_id,
    church_id = EXCLUDED.church_id,
    department_id = EXCLUDED.department_id,
    group_id = EXCLUDED.group_id,
    role = EXCLUDED.role,
    status = EXCLUDED.status,
    ends_at = EXCLUDED.ends_at,
    legacy_member_directory_id = EXCLUDED.legacy_member_directory_id,
    updated_at = now();

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase2_end_membership_on_group_member_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memberships
  SET status = 'ended',
      ends_at = COALESCE(ends_at, now()),
      updated_at = now()
  WHERE legacy_group_member_id = OLD.id;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS phase2_profiles_sync ON public.profiles;
CREATE TRIGGER phase2_profiles_sync
AFTER INSERT OR UPDATE OF church_id, full_name, phone, avatar_url, person_id
ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.phase2_sync_profile();

DROP TRIGGER IF EXISTS phase2_member_directory_sync ON public.member_directory;
CREATE TRIGGER phase2_member_directory_sync
AFTER INSERT OR UPDATE OF church_id, department_id, full_name, phone, profile_id, person_id, family_name, avatar_url
ON public.member_directory
FOR EACH ROW EXECUTE FUNCTION public.phase2_sync_member_directory();

DROP TRIGGER IF EXISTS phase2_group_members_sync ON public.group_members;
CREATE TRIGGER phase2_group_members_sync
AFTER INSERT OR UPDATE OF group_id, profile_id, member_directory_id, role_in_group, is_active
ON public.group_members
FOR EACH ROW EXECUTE FUNCTION public.phase2_sync_group_member();

DROP TRIGGER IF EXISTS phase2_group_members_delete_sync ON public.group_members;
CREATE TRIGGER phase2_group_members_delete_sync
BEFORE DELETE ON public.group_members
FOR EACH ROW EXECUTE FUNCTION public.phase2_end_membership_on_group_member_delete();
