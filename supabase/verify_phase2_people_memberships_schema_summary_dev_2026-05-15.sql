-- Query-compatible summary gate for Phase 2 people/memberships schema.
-- This replaces the older psql-oriented schema inspection file for automated
-- `supabase db query --file` runs.

with target_tables as (
  select unnest(array[
    'people',
    'person_identifiers',
    'member_profiles',
    'memberships'
  ]) as table_name
),
required_columns as (
  select *
  from (values
    ('people', 'id'),
    ('people', 'church_id'),
    ('people', 'display_name'),
    ('people', 'normalized_phone'),
    ('person_identifiers', 'person_id'),
    ('person_identifiers', 'kind'),
    ('person_identifiers', 'value'),
    ('member_profiles', 'person_id'),
    ('member_profiles', 'profile_id'),
    ('member_profiles', 'member_directory_id'),
    ('member_profiles', 'full_name'),
    ('memberships', 'person_id'),
    ('memberships', 'church_id'),
    ('memberships', 'department_id'),
    ('memberships', 'group_id'),
    ('memberships', 'role'),
    ('memberships', 'status'),
    ('memberships', 'legacy_group_member_id'),
    ('memberships', 'legacy_member_directory_id')
  ) as c(table_name, column_name)
),
required_indexes as (
  select unnest(array[
    'idx_people_church_id',
    'idx_people_normalized_phone',
    'idx_person_identifiers_person_id',
    'idx_person_identifiers_auth_user_unique',
    'idx_person_identifiers_legacy_source_kind_unique',
    'idx_member_profiles_person_id',
    'idx_memberships_person_id',
    'idx_memberships_church_department_group',
    'idx_memberships_active'
  ]) as index_name
),
checks as (
  select
    'missing_phase2_tables' as check_name,
    count(*)::bigint as issue_count
  from target_tables tt
  left join information_schema.tables t
    on t.table_schema = 'public'
   and t.table_name = tt.table_name
  where t.table_name is null

  union all

  select
    'phase2_tables_without_rls' as check_name,
    count(*)::bigint as issue_count
  from target_tables tt
  join pg_class c
    on c.relname = tt.table_name
  join pg_namespace n
    on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relrowsecurity = false

  union all

  select
    'missing_required_phase2_columns' as check_name,
    count(*)::bigint as issue_count
  from required_columns rc
  left join information_schema.columns c
    on c.table_schema = 'public'
   and c.table_name = rc.table_name
   and c.column_name = rc.column_name
  where c.column_name is null

  union all

  select
    'phase2_tables_without_primary_key' as check_name,
    count(*)::bigint as issue_count
  from target_tables tt
  left join pg_constraint con
    on con.connamespace = 'public'::regnamespace
   and con.conrelid = ('public.' || tt.table_name)::regclass
   and con.contype = 'p'
  where con.oid is null

  union all

  select
    'missing_required_phase2_indexes' as check_name,
    count(*)::bigint as issue_count
  from required_indexes ri
  left join pg_indexes i
    on i.schemaname = 'public'
   and i.indexname = ri.index_name
  where i.indexname is null
)
select *
from checks
order by check_name;
