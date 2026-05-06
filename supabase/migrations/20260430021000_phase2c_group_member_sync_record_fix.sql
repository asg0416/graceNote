-- Phase 2C correction:
-- Avoid reading fields from an unassigned profile record when group_members.profile_id is NULL.

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
