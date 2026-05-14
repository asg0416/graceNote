-- Verify app_config is protected while the edge function base URL remains readable.

with checks as (
  select
    'app_config_rls_disabled' as check_name,
    count(*)::bigint as issue_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'app_config'
    and c.relrowsecurity = false

  union all

  select
    'app_config_missing_service_role_policy' as check_name,
    case when exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'app_config'
        and p.polname = 'Service role full access on app_config'
    ) then 0::bigint else 1::bigint end as issue_count

  union all

  select
    'app_config_missing_edge_url_read_policy' as check_name,
    case when exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'app_config'
        and p.polname = 'Read edge function base url from app_config'
    ) then 0::bigint else 1::bigint end as issue_count
)
select *
from checks
order by check_name;
