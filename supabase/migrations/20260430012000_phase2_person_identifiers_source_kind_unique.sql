-- Phase 2A correction:
-- The same legacy source row can produce multiple identifier kinds.
-- Example: profiles.id should be stored as both legacy_profile and auth_user.

DROP INDEX IF EXISTS public.idx_person_identifiers_legacy_source_unique;

CREATE UNIQUE INDEX IF NOT EXISTS idx_person_identifiers_legacy_source_kind_unique
  ON public.person_identifiers(kind, source_table, source_id)
  WHERE source_table IS NOT NULL AND source_id IS NOT NULL;
