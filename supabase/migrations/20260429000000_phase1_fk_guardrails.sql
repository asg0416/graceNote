-- Phase 1 guardrail migration:
-- Preserve prayer and attendance records when groups or group memberships are removed.

ALTER TABLE public.prayer_entries
  DROP CONSTRAINT IF EXISTS prayer_entries_group_id_fkey,
  ADD CONSTRAINT prayer_entries_group_id_fkey
    FOREIGN KEY (group_id)
    REFERENCES public.groups(id)
    ON DELETE SET NULL;

ALTER TABLE public.attendance
  DROP CONSTRAINT IF EXISTS attendance_group_member_id_fkey,
  ADD CONSTRAINT attendance_group_member_id_fkey
    FOREIGN KEY (group_member_id)
    REFERENCES public.group_members(id)
    ON DELETE SET NULL;
