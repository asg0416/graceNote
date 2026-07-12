-- Diagnostic telemetry for client-side Gemini calls.
-- Do not store memo contents, API keys, or full provider responses here.

create table public.ai_request_logs (
  id uuid primary key default gen_random_uuid(),
  request_id text not null,
  created_at timestamptz not null default now(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  church_id uuid references public.churches(id) on delete set null,
  group_id uuid references public.groups(id) on delete set null,
  feature text not null default 'parse_prayer_memo',
  model_id text not null,
  attempt_no smallint not null check (attempt_no between 1 and 10),
  outcome text not null check (outcome in (
    'success',
    'http_error',
    'provider_empty',
    'json_parse_error',
    'invalid_result',
    'exception'
  )),
  status_code integer,
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  input_chars integer check (input_chars is null or input_chars >= 0),
  member_count integer check (member_count is null or member_count >= 0),
  matched_count integer check (matched_count is null or matched_count >= 0),
  error_type text,
  error_message text,
  app_version text,
  platform text
);

create index ai_request_logs_created_at_idx
  on public.ai_request_logs (created_at desc);

create index ai_request_logs_group_created_at_idx
  on public.ai_request_logs (group_id, created_at desc);

create index ai_request_logs_request_id_idx
  on public.ai_request_logs (request_id, attempt_no);

alter table public.ai_request_logs enable row level security;

create policy "Authenticated users can insert own AI diagnostics"
  on public.ai_request_logs
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy "Users and church admins can view AI diagnostics"
  on public.ai_request_logs
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or public.check_is_master()
    or public.is_admin_approved(church_id)
  );
