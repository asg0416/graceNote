alter table public.prayer_entries
  add column if not exists draft_content text,
  add column if not exists draft_updated_at timestamptz;

comment on column public.prayer_entries.draft_content is
  'Pending edit saved after a prayer has already been published. Published content remains visible until the next final publish.';

comment on column public.prayer_entries.draft_updated_at is
  'Timestamp for draft_content updates.';

create index if not exists idx_prayer_entries_pending_draft
  on public.prayer_entries(week_id, group_id)
  where draft_content is not null and btrim(draft_content) <> '';
