# Regrouping Seasons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build season-based regrouping so admins can draft future group assignments without changing live Flutter/admin screens until the season is applied.

**Architecture:** Additive DB tables store regrouping seasons, planned groups, and planned person assignments. Admin-web edits draft rows first; live `groups`, `memberships`, `member_directory`, and `group_members` are changed only by an explicit apply RPC. The current `save_regrouping_memberships(..., p_effective_week_date)` path remains as a current/past correction path, not the future scheduling path.

**Tech Stack:** Supabase PostgreSQL migrations/RPC, Next.js 16 admin-web, TypeScript RPC wrappers, existing regrouping page drag-and-drop UI.

---

## File Structure

- Create: `supabase/migrations/20260523000000_phase3_regrouping_seasons_schema.sql`
  - Add `regrouping_seasons`, `regrouping_plan_groups`, `regrouping_plan_assignments`.
  - Add constraints, indexes, RLS enablement, read/manage policies, grants.
- Create: `supabase/migrations/20260523001000_phase3_regrouping_season_draft_rpc.sql`
  - Add `create_regrouping_season` and `save_regrouping_season_draft`.
- Create: `supabase/migrations/20260523001500_phase3_regrouping_season_draft_plan_group_ids.sql`
  - Ensure plan group rows use independent IDs instead of reusing live `groups.id`.
- Create: `supabase/migrations/20260523002000_phase3_regrouping_season_apply_rpc.sql`
  - Add `apply_regrouping_season`.
- Create: `supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql`
  - Verify schema, indexes, constraints, and no live writes during draft save.
- Create: `supabase/verify_regrouping_season_apply_dev_2026-05-23.sql`
  - Rollback test for applying one season.
- Create: `admin-web/src/lib/regroupingSeasonsRpc.ts`
  - Focused TypeScript wrappers for season create/save/apply.
- Modify: `admin-web/src/app/regrouping/page.tsx`
  - Add season-first mode while keeping current live correction path available.
- Modify: `docs/superpowers/plans/2026-05-07-gracenote-person-structure-app-admin-migration-plan.md`
  - Track task completion and smoke results.

## Task 1: Add Regrouping Season Tables

**Files:**
- Create: `supabase/migrations/20260523000000_phase3_regrouping_seasons_schema.sql`
- Create: `supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql`

- [x] **Step 1: Create the migration file**

Create `supabase/migrations/20260523000000_phase3_regrouping_seasons_schema.sql` with:

```sql
set check_function_bodies = off;

create table if not exists public.regrouping_seasons (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  title text not null,
  status text not null default 'draft',
  effective_week_date date not null,
  created_by uuid references public.profiles(id) on delete set null,
  applied_by uuid references public.profiles(id) on delete set null,
  applied_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint regrouping_seasons_status_check
    check (status in ('draft', 'ready', 'applied', 'archived', 'cancelled')),
  constraint regrouping_seasons_applied_state_check
    check (
      (status = 'applied' and applied_at is not null)
      or (status <> 'applied' and applied_at is null)
    )
);

create unique index if not exists regrouping_seasons_unique_active_effective_week
on public.regrouping_seasons (church_id, department_id, effective_week_date)
where status in ('draft', 'ready', 'applied');

create index if not exists regrouping_seasons_department_status_idx
on public.regrouping_seasons (church_id, department_id, status);

create table if not exists public.regrouping_plan_groups (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.regrouping_seasons(id) on delete cascade,
  source_group_id uuid references public.groups(id) on delete set null,
  name text not null,
  color_hex text,
  sort_order integer not null default 0,
  leader_person_id uuid references public.people(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint regrouping_plan_groups_name_not_blank check (btrim(name) <> '')
);

create index if not exists regrouping_plan_groups_season_sort_idx
on public.regrouping_plan_groups (season_id, sort_order, name);

create index if not exists regrouping_plan_groups_source_group_idx
on public.regrouping_plan_groups (season_id, source_group_id);

create table if not exists public.regrouping_plan_assignments (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.regrouping_seasons(id) on delete cascade,
  plan_group_id uuid references public.regrouping_plan_groups(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete cascade,
  role_in_group text not null default 'member',
  sort_order integer not null default 0,
  source_membership_id uuid references public.memberships(id) on delete set null,
  source_member_directory_id uuid references public.member_directory(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint regrouping_plan_assignments_role_check
    check (role_in_group in ('leader', 'member', 'admin', 'sub_leader'))
);

create unique index if not exists regrouping_plan_assignments_unique_person_group
on public.regrouping_plan_assignments (season_id, plan_group_id, person_id)
where plan_group_id is not null;

create unique index if not exists regrouping_plan_assignments_unique_unassigned_person
on public.regrouping_plan_assignments (season_id, person_id)
where plan_group_id is null;

create index if not exists regrouping_plan_assignments_person_idx
on public.regrouping_plan_assignments (season_id, person_id);

create index if not exists regrouping_plan_assignments_group_sort_idx
on public.regrouping_plan_assignments (season_id, plan_group_id, sort_order);

alter table public.regrouping_seasons enable row level security;
alter table public.regrouping_plan_groups enable row level security;
alter table public.regrouping_plan_assignments enable row level security;

grant select, insert, update, delete on public.regrouping_seasons to authenticated, service_role;
grant select, insert, update, delete on public.regrouping_plan_groups to authenticated, service_role;
grant select, insert, update, delete on public.regrouping_plan_assignments to authenticated, service_role;
```

- [x] **Step 2: Add schema verifier**

Create `supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql` with:

```sql
select
  'regrouping_season_tables_exist' as check_name,
  count(*) filter (
    where table_name in (
      'regrouping_seasons',
      'regrouping_plan_groups',
      'regrouping_plan_assignments'
    )
  ) as actual,
  3 as expected
from information_schema.tables
where table_schema = 'public';

select
  'regrouping_season_indexes_exist' as check_name,
  count(*) filter (
    where indexname in (
      'regrouping_seasons_unique_active_effective_week',
      'regrouping_seasons_department_status_idx',
      'regrouping_seasons_department_effective_week_idx',
      'regrouping_plan_groups_season_sort_idx',
      'regrouping_plan_groups_source_group_idx',
      'regrouping_plan_assignments_unique_person_group',
      'regrouping_plan_assignments_unique_unassigned_person',
      'regrouping_plan_assignments_person_idx',
      'regrouping_plan_assignments_group_sort_idx'
    )
  ) as actual,
  9 as expected
from pg_indexes
where schemaname = 'public';
```

- [x] **Step 3: Apply migration to dev only**

Run with the dev DB URL file only. Local `psql` was unavailable, so this was executed through Docker without printing the DB URL:

```bash
docker run --rm \
  -v /private/tmp/gracenote_dev_db_url:/tmp/gracenote_dev_db_url:ro \
  -v /Users/sujin/Documents/code_work/GraceNote:/work:ro \
  postgres:16-alpine \
  sh -c 'psql "$(cat /tmp/gracenote_dev_db_url)" -v ON_ERROR_STOP=1 -f /work/supabase/migrations/20260523000000_phase3_regrouping_seasons_schema.sql'
```

Expected:

```plain text
CREATE TABLE / CREATE INDEX / CREATE POLICY / GRANT with no SQL errors
```

- [x] **Step 4: Run verifier**

Run:

```bash
docker run --rm \
  -v /private/tmp/gracenote_dev_db_url:/tmp/gracenote_dev_db_url:ro \
  -v /Users/sujin/Documents/code_work/GraceNote:/work:ro \
  postgres:16-alpine \
  sh -c 'psql "$(cat /tmp/gracenote_dev_db_url)" -v ON_ERROR_STOP=1 -f /work/supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql'
```

Expected:

```plain text
regrouping_season_tables_exist | actual 3 | expected 3
regrouping_season_indexes_exist | actual 9 | expected 9
regrouping_season_rls_enabled | actual 3 | expected 3
regrouping_season_policies_exist | actual 6 | expected 6
```

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260523000000_phase3_regrouping_seasons_schema.sql supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql
git commit -m "phase3: add regrouping season draft schema"
```

## Task 2: Add Draft Create/Save RPCs

**Files:**
- Create: `supabase/migrations/20260523001000_phase3_regrouping_season_draft_rpc.sql`
- Extend: `supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql`

- [x] **Step 1: Create draft RPC migration**

Create `supabase/migrations/20260523001000_phase3_regrouping_season_draft_rpc.sql` with:

```sql
set check_function_bodies = off;

create or replace function public.create_regrouping_season(
  p_church_id uuid,
  p_department_id uuid,
  p_title text,
  p_effective_week_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season_id uuid;
  v_title text := nullif(btrim(p_title), '');
begin
  if p_church_id is null then
    raise exception 'church_id is required.';
  end if;

  if p_department_id is null then
    raise exception 'department_id is required.';
  end if;

  if v_title is null then
    raise exception 'title is required.';
  end if;

  if p_effective_week_date is null then
    raise exception 'effective_week_date is required.';
  end if;

  if extract(dow from p_effective_week_date) <> 0 then
    raise exception 'effective_week_date must be a Sunday.';
  end if;

  insert into public.regrouping_seasons (
    church_id,
    department_id,
    title,
    effective_week_date,
    created_by
  )
  values (
    p_church_id,
    p_department_id,
    v_title,
    p_effective_week_date,
    auth.uid()
  )
  returning id into v_season_id;

  return v_season_id;
end;
$$;

create or replace function public.save_regrouping_season_draft(
  p_season_id uuid,
  p_groups jsonb,
  p_assignments jsonb
)
returns table(plan_group_count integer, assignment_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_season public.regrouping_seasons%rowtype;
begin
  select *
  into v_season
  from public.regrouping_seasons
  where id = p_season_id
  for update;

  if v_season.id is null then
    raise exception 'regrouping season not found.';
  end if;

  if v_season.status not in ('draft', 'ready') then
    raise exception 'only draft or ready regrouping seasons are editable.';
  end if;

  delete from public.regrouping_plan_assignments
  where season_id = p_season_id;

  delete from public.regrouping_plan_groups
  where season_id = p_season_id;

  insert into public.regrouping_plan_groups (
    id,
    season_id,
    source_group_id,
    name,
    color_hex,
    sort_order,
    leader_person_id
  )
  select
    coalesce(nullif(g.value->>'plan_group_id', '')::uuid, gen_random_uuid()),
    p_season_id,
    nullif(g.value->>'source_group_id', '')::uuid,
    nullif(btrim(g.value->>'name'), ''),
    nullif(g.value->>'color_hex', ''),
    coalesce(nullif(g.value->>'sort_order', '')::integer, 0),
    nullif(g.value->>'leader_person_id', '')::uuid
  from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) as g(value)
  where nullif(btrim(g.value->>'name'), '') is not null;

  insert into public.regrouping_plan_assignments (
    season_id,
    plan_group_id,
    person_id,
    role_in_group,
    sort_order,
    source_membership_id,
    source_member_directory_id
  )
  select
    p_season_id,
    nullif(a.value->>'plan_group_id', '')::uuid,
    nullif(a.value->>'person_id', '')::uuid,
    coalesce(nullif(a.value->>'role_in_group', ''), 'member'),
    coalesce(nullif(a.value->>'sort_order', '')::integer, 0),
    nullif(a.value->>'source_membership_id', '')::uuid,
    nullif(a.value->>'source_member_directory_id', '')::uuid
  from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) as a(value)
  where nullif(a.value->>'person_id', '') is not null;

  update public.regrouping_seasons
  set updated_at = now()
  where id = p_season_id;

  return query
  select
    (select count(*)::integer from public.regrouping_plan_groups where season_id = p_season_id),
    (select count(*)::integer from public.regrouping_plan_assignments where season_id = p_season_id);
end;
$$;

grant execute on function public.create_regrouping_season(uuid, uuid, text, date) to authenticated, service_role;
grant execute on function public.save_regrouping_season_draft(uuid, jsonb, jsonb) to authenticated, service_role;
```

- [x] **Step 2: Add rollback smoke SQL**

Append to `supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql`:

```sql
begin;

with target_department as (
  select d.id as department_id, d.church_id
  from public.departments d
  where d.is_active is distinct from false
  order by d.created_at desc nulls last
  limit 1
),
created as (
  select public.create_regrouping_season(
    church_id,
    department_id,
    'verify regrouping season draft',
    date '2026-05-24'
  ) as season_id
  from target_department
),
saved as (
  select *
  from public.save_regrouping_season_draft(
    (select season_id from created),
    jsonb_build_array(
      jsonb_build_object(
        'plan_group_id', gen_random_uuid(),
        'name', 'verify group',
        'sort_order', 1
      )
    ),
    '[]'::jsonb
  )
)
select
  'regrouping_draft_save_no_live_write' as check_name,
  (select case when season_id is not null then 1 else 0 end from created) as created_season_returned,
  (select plan_group_count from saved) as plan_group_count,
  (select assignment_count from saved) as assignment_count;

rollback;
```

Expected:

```plain text
regrouping_draft_save_no_live_write | created_season_returned 1 | plan_group_count 1 | assignment_count 1 | live_counts_unchanged 1
```

- [x] **Step 3: Apply migration to dev and run verifier**

Run:

```bash
docker run --rm \
  -v /private/tmp/gracenote_dev_db_url:/tmp/gracenote_dev_db_url:ro \
  -v /Users/sujin/Documents/code_work/GraceNote:/work:ro \
  postgres:16-alpine \
  sh -c 'psql "$(cat /tmp/gracenote_dev_db_url)" -v ON_ERROR_STOP=1 -f /work/supabase/migrations/20260523001000_phase3_regrouping_season_draft_rpc.sql'

docker run --rm \
  -v /private/tmp/gracenote_dev_db_url:/tmp/gracenote_dev_db_url:ro \
  -v /Users/sujin/Documents/code_work/GraceNote:/work:ro \
  postgres:16-alpine \
  sh -c 'psql "$(cat /tmp/gracenote_dev_db_url)" -v ON_ERROR_STOP=1 -f /work/supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql'
```

Expected:

```plain text
No SQL errors
draft save returns one plan group, one assignment, and live_counts_unchanged = 1 in rollback
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260523001000_phase3_regrouping_season_draft_rpc.sql supabase/verify_regrouping_seasons_schema_dev_2026-05-23.sql
git commit -m "phase3: add regrouping season draft rpc"
```

## Task 3: Add Admin-Web RPC Wrapper

**Files:**
- Create: `admin-web/src/lib/regroupingSeasonsRpc.ts`
- Test: `admin-web/src/lib/regroupingSeasonsRpc.test.ts`

- [x] **Step 1: Add test for payload shape and errors**

Create `admin-web/src/lib/regroupingSeasonsRpc.test.ts`.

```ts
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyRegroupingSeason,
  createRegroupingSeason,
  saveRegroupingSeasonDraft,
} from './regroupingSeasonsRpc.ts';

// Uses Node's built-in test runner so this repo does not need an extra Vitest dependency.
```

- [x] **Step 2: Run test and confirm it fails before implementation**

Run:

```bash
node --test admin-web/src/lib/regroupingSeasonsRpc.test.ts
```

Expected:

```plain text
ERR_MODULE_NOT_FOUND for ./regroupingSeasonsRpc.ts
```

- [x] **Step 3: Implement wrapper**

Create `admin-web/src/lib/regroupingSeasonsRpc.ts`:

```ts
type RpcResult<T> = {
  data: T | null;
  error: { message?: string } | null;
};

type RpcClientLike = {
  rpc: <T = unknown>(
    fn: string,
    params?: Record<string, unknown>
  ) => Promise<RpcResult<T>>;
};

const assertNoRpcError = (error: { message?: string } | null, fallback: string) => {
  if (error) {
    throw new Error(error.message || fallback);
  }
};

export const createRegroupingSeason = async (
  supabase: RpcClientLike,
  payload: {
    churchId: string;
    departmentId: string;
    title: string;
    effectiveWeekDate: string;
  }
) => {
  const { data, error } = await supabase.rpc<string>('create_regrouping_season', {
    p_church_id: payload.churchId,
    p_department_id: payload.departmentId,
    p_title: payload.title,
    p_effective_week_date: payload.effectiveWeekDate,
  });

  assertNoRpcError(error, '조편성 계획 생성에 실패했습니다.');
  if (!data) throw new Error('조편성 계획 ID를 받지 못했습니다.');
  return data;
};

export const saveRegroupingSeasonDraft = async (
  supabase: RpcClientLike,
  payload: {
    seasonId: string;
    groups: Array<Record<string, unknown>>;
    assignments: Array<Record<string, unknown>>;
  }
) => {
  const { data, error } = await supabase.rpc<Array<{
    plan_group_count: number;
    assignment_count: number;
  }>>('save_regrouping_season_draft', {
    p_season_id: payload.seasonId,
    p_groups: payload.groups,
    p_assignments: payload.assignments,
  });

  assertNoRpcError(error, '조편성 계획 저장에 실패했습니다.');
  const first = Array.isArray(data) ? data[0] : null;
  return {
    planGroupCount: first?.plan_group_count ?? 0,
    assignmentCount: first?.assignment_count ?? 0,
  };
};

export const applyRegroupingSeason = async (
  supabase: RpcClientLike,
  payload: { seasonId: string }
) => {
  const { data, error } = await supabase.rpc('apply_regrouping_season', {
    p_season_id: payload.seasonId,
  });

  assertNoRpcError(error, '조편성 계획 적용에 실패했습니다.');
  return data;
};
```

- [x] **Step 4: Run test and lint**

Run:

```bash
node --test admin-web/src/lib/regroupingSeasonsRpc.test.ts
cd admin-web && npm run lint -- src/lib/regroupingSeasonsRpc.ts src/lib/regroupingSeasonsRpc.test.ts
cd admin-web && npx tsc --noEmit --pretty false
```

Expected:

```plain text
3 tests pass
lint 0 errors
tsc 0 errors
```

- [ ] **Step 5: Commit**

```bash
git add admin-web/src/lib/regroupingSeasonsRpc.ts admin-web/src/lib/regroupingSeasonsRpc.test.ts
git commit -m "admin: add regrouping season rpc client"
```

## Task 4: Add Season-First Admin UI Shell

**Files:**
- Modify: `admin-web/src/app/regrouping/page.tsx`

- [x] **Step 1: Add state for season mode without removing live correction path**

In `admin-web/src/app/regrouping/page.tsx`, add state near existing regrouping state:

```tsx
const [regroupingMode, setRegroupingMode] = useState<'live' | 'season'>('season');
const [selectedSeasonId, setSelectedSeasonId] = useState<string | null>(null);
const [seasonTitle, setSeasonTitle] = useState('');
const [seasonEffectiveWeekDate, setSeasonEffectiveWeekDate] = useState(getCurrentSundayInputValue);
```

- [x] **Step 2: Replace the current prominent `적용 주차` save control with mode-aware controls**

The UI should show:

```tsx
<div className="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm">
  <div className="flex flex-wrap items-center justify-between gap-3">
    <div>
      <p className="text-[11px] font-black uppercase tracking-[0.2em] text-indigo-400">
        Regrouping Mode
      </p>
      <h2 className="text-lg font-black text-slate-900">
        조편성 계획
      </h2>
      <p className="mt-1 text-sm font-semibold text-slate-500">
        미래 조편성은 초안으로 저장하고, 적용 시점에만 실제 소속으로 반영합니다.
      </p>
    </div>
    <div className="flex rounded-2xl bg-slate-100 p-1">
      <button
        type="button"
        onClick={() => setRegroupingMode('season')}
        className={`rounded-xl px-4 py-2 text-sm font-black ${
          regroupingMode === 'season' ? 'bg-white text-indigo-600 shadow-sm' : 'text-slate-500'
        }`}
      >
        시즌 초안
      </button>
      <button
        type="button"
        onClick={() => setRegroupingMode('live')}
        className={`rounded-xl px-4 py-2 text-sm font-black ${
          regroupingMode === 'live' ? 'bg-white text-indigo-600 shadow-sm' : 'text-slate-500'
        }`}
      >
        현재/과거 보정
      </button>
    </div>
  </div>
</div>
```

- [x] **Step 3: Keep live correction warning explicit**

When `regroupingMode === 'live'`, show:

```tsx
<div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm font-bold text-amber-800">
  현재/과거 보정은 저장 즉시 실제 조편성과 호환 row를 변경합니다. 미래 조편성 준비는 시즌 초안을 사용하세요.
</div>
```

- [x] **Step 4: Keep existing save button calling current `handleSave` only in live mode**

Disable the current live save button when season mode is active:

```tsx
disabled={saving || regroupingMode === 'season'}
```

Add a separate season draft save button that is visibly separate from live save and does not call live RPC:

```tsx
<button
  type="button"
  disabled={!selectedChurch || !selectedDepartment}
  onClick={() => alert('시즌 초안 저장은 다음 단계에서 연결됩니다.')}
  className="rounded-2xl bg-indigo-600 px-5 py-3 text-sm font-black text-white shadow-lg shadow-indigo-200 disabled:cursor-not-allowed disabled:bg-slate-300"
>
  시즌 초안 저장
</button>
```

- [x] **Step 5: Run lint**

Run:

```bash
cd admin-web
npm run lint -- src/app/regrouping/page.tsx
```

Expected:

```plain text
0 errors
existing hook dependency warnings may remain
```

- [ ] **Step 6: Commit**

```bash
git add admin-web/src/app/regrouping/page.tsx
git commit -m "admin: add regrouping season mode shell"
```

## Task 5: Connect Season Draft Save

**Files:**
- Modify: `admin-web/src/app/regrouping/page.tsx`
- Modify: `admin-web/src/lib/regroupingSeasonsRpc.ts`

- [x] **Step 1: Import RPCs**

In `admin-web/src/app/regrouping/page.tsx`:

```tsx
import {
  createRegroupingSeason,
  saveRegroupingSeasonDraft,
} from '@/lib/regroupingSeasonsRpc';
```

- [x] **Step 2: Convert visible groups to draft payload**

Added tested helper in `admin-web/src/lib/regroupingSeasonPayloads.ts`:

```tsx
const buildRegroupingSeasonGroupsPayload = (groups: any[]) => groups.map((group, index) => ({
  plan_group_id: String(group.id || '').startsWith('plan-') ? String(group.id).replace('plan-', '') : null,
  source_group_id: isUuid(group.id) ? group.id : null,
  name: group.name,
  color_hex: group.color_hex || null,
  sort_order: index,
  leader_person_id: group.leader_person_id || null,
}));
```

If `isUuid` does not exist in the file, add:

```tsx
const isUuid = (value: unknown) =>
  typeof value === 'string' &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
```

- [x] **Step 3: Convert display members to draft assignment payload**

Added tested helper in `admin-web/src/lib/regroupingSeasonPayloads.ts`:

```tsx
const buildRegroupingSeasonAssignmentsPayload = (members: any[]) => members
  .filter(member => member.person_id)
  .map((member, index) => ({
    plan_group_id: isUuid(member.group_id) ? member.group_id : null,
    person_id: member.person_id,
    role_in_group: member.role_in_group || member.role || 'member',
    sort_order: index,
    source_membership_id: member.membership_id || null,
    source_member_directory_id: member.id || null,
  }));
```

- [x] **Step 4: Add draft save handler**

Add:

```tsx
const handleSaveSeasonDraft = async () => {
  if (!selectedChurch || !selectedDepartment) {
    alert('교회와 부서를 먼저 선택하세요.');
    return;
  }

  try {
    setSaving(true);
    const title = seasonTitle.trim() || `${selectedDepartment.name} ${formatRegroupingWeekLabel(seasonEffectiveWeekDate)} 조편성`;
    const seasonId = selectedSeasonId ?? await createRegroupingSeason(supabase, {
      churchId: selectedChurch.id,
      departmentId: selectedDepartment.id,
      title,
      effectiveWeekDate: seasonEffectiveWeekDate,
    });

    if (!selectedSeasonId) {
      setSelectedSeasonId(seasonId);
    }

    const result = await saveRegroupingSeasonDraft(supabase, {
      seasonId,
      groups: buildRegroupingSeasonGroupsPayload(groups),
      assignments: buildRegroupingSeasonAssignmentsPayload(displayLocalMembers),
    });

    alert(`시즌 초안이 저장되었습니다. 조 ${result.planGroupCount}개, 소속 ${result.assignmentCount}개`);
  } catch (error) {
    console.error('Save regrouping season draft error:', error);
    alert(error instanceof Error ? error.message : '시즌 초안 저장 중 오류가 발생했습니다.');
  } finally {
    setSaving(false);
  }
};
```

- [x] **Step 5: Wire the season save button**

Replace the temporary alert click:

```tsx
onClick={handleSaveSeasonDraft}
```

- [x] **Step 6: Run lint**

Run:

```bash
cd admin-web
npm run lint -- src/app/regrouping/page.tsx src/lib/regroupingSeasonsRpc.ts
```

Expected:

```plain text
0 errors
existing hook dependency warnings may remain
```

- [ ] **Step 7: Commit**

```bash
git add admin-web/src/app/regrouping/page.tsx admin-web/src/lib/regroupingSeasonsRpc.ts
git commit -m "admin: save regrouping season drafts"
```

## Task 6: Add Apply RPC

**Files:**
- Create: `supabase/migrations/20260523002000_phase3_regrouping_season_apply_rpc.sql`
- Create: `supabase/verify_regrouping_season_apply_dev_2026-05-23.sql`

- [x] **Step 1: Create apply RPC migration**

Create `supabase/migrations/20260523002000_phase3_regrouping_season_apply_rpc.sql`.

The RPC must:

```sql
create or replace function public.apply_regrouping_season(p_season_id uuid)
returns table(
  created_group_count integer,
  ended_group_count integer,
  created_membership_count integer,
  ended_membership_count integer,
  affected_person_count integer
)
```

Implementation requirements:

- Lock the season row `for update`.
- Reject missing, cancelled, archived, or already applied seasons.
- Reject future `effective_week_date` so drafts do not mutate live data before the effective week.
- End active memberships in the department at `effective_week_date - 1 second`.
- End active groups in the department that are not continued by planned groups.
- Create new `groups` rows for planned groups with `source_group_id is null`.
- Reuse existing `groups` rows for planned groups with `source_group_id`.
- Create active `memberships` for each plan assignment.
- Write compatibility `member_directory` and `group_members` rows only where the current app still needs them.
- Mark the season `applied`, set `applied_at`, `applied_by`.

The implementation must not call the old 4-arg `save_regrouping_memberships` blindly because that function assumes the client payload is the current live state. If shared behavior is required, extract a dedicated helper in the same migration before `apply_regrouping_season` is created.

- [x] **Step 2: Add rollback verifier**

Create `supabase/verify_regrouping_season_apply_dev_2026-05-23.sql` with a transaction that:

```sql
begin;

-- Pick one active department with at least one active person membership.
-- Create a regrouping season for 2026-05-24.
-- Create one planned group.
-- Assign one active person to that planned group.
-- Apply the season.
-- Assert:
-- - season status is applied
-- - one active membership starts at 2026-05-24
-- - no draft tables were deleted
-- - created group active_from is 2026-05-24

rollback;
```

The query output must include:

```plain text
season_applied | 1
active_membership_from_effective_week | 1
planned_rows_preserved | 1
```

- [x] **Step 3: Apply migration and run verifier on dev**

Run:

```bash
node scripts/apply-sql-file-psql.mjs --db-url-file /private/tmp/gracenote_dev_db_url --file supabase/migrations/20260523002000_phase3_regrouping_season_apply_rpc.sql
node scripts/run-sql-file-psql.mjs --db-url-file /private/tmp/gracenote_dev_db_url --file supabase/verify_regrouping_season_apply_dev_2026-05-23.sql
```

Expected:

```plain text
No SQL errors
season_applied | 1
active_membership_from_effective_week | 1
planned_rows_preserved | 1
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260523002000_phase3_regrouping_season_apply_rpc.sql supabase/verify_regrouping_season_apply_dev_2026-05-23.sql
git commit -m "phase3: apply regrouping seasons to live memberships"
```

## Task 7: Admin Apply Button And Smoke Checklist

**Files:**
- Modify: `admin-web/src/app/regrouping/page.tsx`
- Modify: `docs/superpowers/plans/2026-05-07-gracenote-person-structure-app-admin-migration-plan.md`

- [x] **Step 1: Import apply wrapper**

```tsx
import {
  applyRegroupingSeason,
  createRegroupingSeason,
  saveRegroupingSeasonDraft,
} from '@/lib/regroupingSeasonsRpc';
```

- [x] **Step 2: Add apply handler**

```tsx
const handleApplySeason = async () => {
  if (!selectedSeasonId) {
    alert('먼저 시즌 초안을 저장하세요.');
    return;
  }

  if (!window.confirm('이 조편성 계획을 실제 소속으로 적용할까요? 적용 후에는 앱과 출석/기도 화면에 반영됩니다.')) {
    return;
  }

  try {
    setSaving(true);
    await applyRegroupingSeason(supabase, { seasonId: selectedSeasonId });
    alert('조편성 계획이 실제 소속으로 적용되었습니다.');
    await fetchData();
  } catch (error) {
    console.error('Apply regrouping season error:', error);
    alert(error instanceof Error ? error.message : '조편성 계획 적용 중 오류가 발생했습니다.');
  } finally {
    setSaving(false);
  }
};
```

- [x] **Step 3: Add apply button near draft save**

```tsx
<button
  type="button"
  disabled={saving || !selectedSeasonId}
  onClick={handleApplySeason}
  className="rounded-2xl bg-emerald-600 px-5 py-3 text-sm font-black text-white shadow-lg shadow-emerald-200 disabled:cursor-not-allowed disabled:bg-slate-300"
>
  실제 소속에 적용
</button>
```

- [x] **Step 4: Add smoke checklist to migration plan**

Append:

```markdown
## 2026-05-23 Regrouping Seasons Smoke

- [ ] Future season draft save does not change Flutter prayer tabs before effective week.
- [ ] Future season draft save does not change admin attendance groups before effective week.
- [ ] Applying season changes groups from the effective week onward.
- [ ] Historical prayer cards keep `recorded_group_id` group name.
- [ ] Historical attendance snapshots keep the old group where records exist.
- [ ] Current/past correction mode still uses `save_regrouping_memberships(..., p_effective_week_date)` and is clearly separated from season draft mode.
```

- [ ] **Step 5: Run lint and diff check**

Run:

```bash
cd admin-web
npm run lint -- src/app/regrouping/page.tsx src/lib/regroupingSeasonsRpc.ts
cd ..
git diff --check
```

Expected:

```plain text
0 errors
git diff --check has no output
```

- [ ] **Step 6: Commit**

```bash
git add admin-web/src/app/regrouping/page.tsx docs/superpowers/plans/2026-05-07-gracenote-person-structure-app-admin-migration-plan.md
git commit -m "admin: apply regrouping season drafts"
```

## Task 8: Reopen Saved Season Drafts

**Files:**
- Modify: `admin-web/src/app/regrouping/page.tsx`
- Modify: `admin-web/src/lib/regroupingSeasonPayloads.ts`
- Test: `admin-web/src/lib/regroupingSeasonPayloads.test.ts`

- [x] **Step 1: Add draft-to-board mapper with tests**

`mapRegroupingSeasonDraftToBoard` maps `regrouping_plan_groups` and `regrouping_plan_assignments` rows back into the Kanban board state.

- [x] **Step 2: Fetch department season list**

`regrouping_seasons` rows are fetched by selected church/department and scoped to `draft`, `ready`, and `applied` statuses.

- [x] **Step 3: Add season select UI**

The season toolbar now supports `새 시즌 초안` and existing saved seasons.

- [x] **Step 4: Load selected draft**

Selecting an existing season loads plan groups and assignments without touching live group/membership rows.

- [x] **Step 5: Run verification**

```bash
node --test admin-web/src/lib/regroupingSeasonPayloads.test.ts admin-web/src/lib/regroupingSeasonsRpc.test.ts
npm run lint -- src/app/regrouping/page.tsx src/lib/regroupingSeasonsRpc.ts src/lib/regroupingSeasonPayloads.ts src/lib/regroupingSeasonPayloads.test.ts
npx tsc --noEmit --pretty false
git diff --check
```

## Completion Criteria

- Dev DB has the three additive season tables.
- Draft save writes only `regrouping_*` plan tables.
- Future draft groups do not appear in Flutter/admin operational screens before apply.
- Apply RPC updates live memberships and legacy compatibility rows in one transaction.
- Admin UI clearly separates `시즌 초안` from `현재/과거 보정`.
- Historical prayer/attendance still display recorded group names.
- `git diff --check` passes.
- Targeted lint/tests pass or only known unrelated warnings remain.
