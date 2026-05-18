-- Phase 2A additive schema draft:
-- Introduce canonical people and membership tables without removing legacy tables.

CREATE TABLE IF NOT EXISTS public.people (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id uuid NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  normalized_phone text,
  primary_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.person_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id uuid NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (
    kind IN ('phone', 'auth_user', 'legacy_profile', 'legacy_directory')
  ),
  value text NOT NULL,
  source_table text,
  source_id uuid,
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.member_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id uuid NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  profile_id uuid UNIQUE REFERENCES public.profiles(id) ON DELETE SET NULL,
  member_directory_id uuid UNIQUE REFERENCES public.member_directory(id) ON DELETE SET NULL,
  full_name text NOT NULL,
  phone text,
  avatar_url text,
  family_name text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id uuid NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  church_id uuid NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  department_id uuid REFERENCES public.departments(id) ON DELETE SET NULL,
  group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member', 'teacher', 'assistant')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'ended')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  legacy_group_member_id uuid UNIQUE REFERENCES public.group_members(id) ON DELETE SET NULL,
  legacy_member_directory_id uuid REFERENCES public.member_directory(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at IS NULL OR ends_at >= starts_at)
);

CREATE INDEX IF NOT EXISTS idx_people_church_id
  ON public.people(church_id);

CREATE INDEX IF NOT EXISTS idx_people_normalized_phone
  ON public.people(church_id, normalized_phone)
  WHERE normalized_phone IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_person_identifiers_person_id
  ON public.person_identifiers(person_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_person_identifiers_auth_user_unique
  ON public.person_identifiers(value)
  WHERE kind = 'auth_user';

CREATE UNIQUE INDEX IF NOT EXISTS idx_person_identifiers_legacy_source_unique
  ON public.person_identifiers(source_table, source_id)
  WHERE source_table IS NOT NULL AND source_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_member_profiles_person_id
  ON public.member_profiles(person_id);

CREATE INDEX IF NOT EXISTS idx_memberships_person_id
  ON public.memberships(person_id);

CREATE INDEX IF NOT EXISTS idx_memberships_church_department_group
  ON public.memberships(church_id, department_id, group_id);

CREATE INDEX IF NOT EXISTS idx_memberships_active
  ON public.memberships(church_id, status)
  WHERE status = 'active';

ALTER TABLE public.people ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.person_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

-- Intentionally no broad authenticated policies yet.
-- Phase 2B/2C must define read/write policy boundaries before app read switch.
