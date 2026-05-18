-- Phase 2 correction:
-- 1. Directory rows with group_name but no group_members row still need memberships.
-- 2. group_members rows pointing to deleted member_directory rows must not appear as active.

CREATE UNIQUE INDEX IF NOT EXISTS idx_memberships_directory_only_unique
  ON public.memberships(legacy_member_directory_id)
  WHERE legacy_group_member_id IS NULL
    AND legacy_member_directory_id IS NOT NULL;

UPDATE public.memberships m
SET status = 'ended',
    ends_at = COALESCE(m.ends_at, now()),
    updated_at = now()
FROM public.group_members gm
LEFT JOIN public.member_directory md ON md.id = gm.member_directory_id
WHERE m.legacy_group_member_id = gm.id
  AND gm.member_directory_id IS NOT NULL
  AND md.id IS NULL
  AND m.status = 'active';

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
SELECT
  person_seed.person_id,
  md.church_id,
  md.department_id,
  g.id AS group_id,
  CASE
    WHEN md.role_in_group = 'leader' THEN 'leader'
    ELSE 'member'
  END AS role,
  CASE
    WHEN COALESCE(md.is_active, true) THEN 'active'
    ELSE 'inactive'
  END AS status,
  COALESCE(md.joined_at, md.created_at, now()) AS starts_at,
  CASE
    WHEN COALESCE(md.is_active, true) THEN NULL
    ELSE COALESCE(md.left_at, now())
  END AS ends_at,
  md.id AS legacy_member_directory_id
FROM public.member_directory md
JOIN public.groups g
  ON g.church_id = md.church_id
 AND g.department_id = md.department_id
 AND g.name = md.group_name
CROSS JOIN LATERAL (
  SELECT public.phase2_upsert_person(
    md.church_id,
    md.person_id,
    md.profile_id,
    md.id,
    md.full_name,
    md.phone
  ) AS person_id
) person_seed
WHERE md.church_id IS NOT NULL
  AND md.group_name IS NOT NULL
  AND md.group_name <> ''
  AND NOT EXISTS (
    SELECT 1
    FROM public.group_members gm
    WHERE gm.member_directory_id = md.id
      AND gm.is_active = true
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
  v_status text;
  v_ends_at timestamptz;
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
  v_status := CASE
    WHEN COALESCE(NEW.is_active, true)
      AND (NEW.member_directory_id IS NULL OR v_directory.id IS NOT NULL) THEN 'active'
    WHEN NEW.member_directory_id IS NOT NULL AND v_directory.id IS NULL THEN 'ended'
    ELSE 'inactive'
  END;
  v_ends_at := CASE
    WHEN v_status = 'active' THEN NULL
    ELSE now()
  END;

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
    v_status,
    COALESCE(NEW.joined_at, now()),
    v_ends_at,
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
