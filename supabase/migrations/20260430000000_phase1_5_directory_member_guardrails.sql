-- Phase 1.5 guardrail migration:
-- Preserve attendance and prayer records when member_directory rows are removed.

ALTER TABLE public.attendance
  DROP CONSTRAINT IF EXISTS attendance_directory_member_id_fkey,
  ADD CONSTRAINT attendance_directory_member_id_fkey
    FOREIGN KEY (directory_member_id)
    REFERENCES public.member_directory(id)
    ON DELETE SET NULL;

ALTER TABLE public.prayer_entries
  DROP CONSTRAINT IF EXISTS prayer_entries_directory_member_id_fkey,
  ADD CONSTRAINT prayer_entries_directory_member_id_fkey
    FOREIGN KEY (directory_member_id)
    REFERENCES public.member_directory(id)
    ON DELETE SET NULL;
