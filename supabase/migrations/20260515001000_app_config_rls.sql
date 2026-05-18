-- Enable RLS for app_config in the migration chain.
--
-- app_config is currently used by notify_on_event() to read the public Edge
-- Function base URL. Keep writes service-role only, and expose only that
-- non-secret key for trigger/client roles that may execute the function.

alter table public.app_config enable row level security;

drop policy if exists "Service role full access on app_config" on public.app_config;
create policy "Service role full access on app_config"
  on public.app_config
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists "Read edge function base url from app_config" on public.app_config;
create policy "Read edge function base url from app_config"
  on public.app_config
  for select
  to anon, authenticated
  using (key = 'edge_function_base_url');
