-- Phase 2 read policies:
-- Allow approved admins to inspect additive identity/membership tables.

CREATE POLICY "Phase2 people admin select"
  ON public.people
  FOR SELECT
  TO authenticated
  USING (
    public.check_is_master()
    OR public.is_admin_approved(church_id)
    OR church_id = public.get_my_church_id()
  );

CREATE POLICY "Phase2 person identifiers admin select"
  ON public.person_identifiers
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.people p
      WHERE p.id = person_identifiers.person_id
        AND (
          public.check_is_master()
          OR public.is_admin_approved(p.church_id)
          OR p.church_id = public.get_my_church_id()
        )
    )
  );

CREATE POLICY "Phase2 member profiles admin select"
  ON public.member_profiles
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.people p
      WHERE p.id = member_profiles.person_id
        AND (
          public.check_is_master()
          OR public.is_admin_approved(p.church_id)
          OR p.church_id = public.get_my_church_id()
        )
    )
  );

CREATE POLICY "Phase2 memberships admin select"
  ON public.memberships
  FOR SELECT
  TO authenticated
  USING (
    public.check_is_master()
    OR public.is_admin_approved(church_id)
    OR church_id = public.get_my_church_id()
  );
