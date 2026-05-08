# GraceNote Attendance Roster Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add week+department attendance roster snapshots so attendance denominators are stored, editable by admins, and no longer inferred from current roster or submitted attendance rows.

**Architecture:** Create snapshot header/member/event tables and RPCs first. Switch admin attendance reads to the snapshot denominator while keeping existing `attendance.directory_member_id` writes. Add admin UI controls to edit the selected week's roster like an Excel attendance sheet.

**Tech Stack:** Supabase Postgres migrations/RPC/RLS, Next.js admin-web, TypeScript helper tests with `node --test`, targeted ESLint, dev Supabase verification SQL.

---

## Source Spec

`docs/superpowers/specs/2026-05-08-gracenote-attendance-roster-snapshot-design.md`

## Current Context

Current attendance dashboard code already has temporary person-based metric helpers:

- `admin-web/src/lib/attendanceMetrics.ts`
- `admin-web/src/lib/attendanceMetrics.test.ts`
- `admin-web/src/app/attendance/page.tsx`

Those helpers are temporary. Once snapshot reads are live, denominator logic should come from snapshot rows, not current roster backfill inference.

## File Map

| File | Responsibility |
| --- | --- |
| `supabase/migrations/20260508000000_attendance_roster_snapshots.sql` | Snapshot tables, indexes, RLS, RPCs |
| `supabase/verify_attendance_roster_snapshots_dev_2026-05-08.sql` | Dev verification and rollback-style checks |
| `admin-web/src/lib/attendanceRosterSnapshots.ts` | Supabase read/write helpers for snapshot data |
| `admin-web/src/lib/attendanceRosterSnapshots.test.ts` | Pure unit tests for transformation helpers |
| `admin-web/src/lib/attendanceMetrics.ts` | Simplify metrics to snapshot target members |
| `admin-web/src/app/attendance/page.tsx` | Use snapshot denominator, status card, inline edit handlers |
| `docs/superpowers/plans/2026-05-03-gracenote-phase2-prod-rollout-manifest.md` | Prod execution gate update |
| Notion `GraceNote 출석 대상 Snapshot 설계` | Human-readable decision log |

---

## Task 1: DB Schema And RPCs

**Files:**
- Create: `supabase/migrations/20260508000000_attendance_roster_snapshots.sql`
- Create: `supabase/verify_attendance_roster_snapshots_dev_2026-05-08.sql`

- [x] **Step 1: Write migration table DDL**

Create `supabase/migrations/20260508000000_attendance_roster_snapshots.sql`:

```sql
begin;

create table if not exists public.attendance_roster_snapshots (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id) on delete restrict,
  department_id uuid not null references public.departments(id) on delete restrict,
  week_id uuid not null references public.weeks(id) on delete restrict,
  status text not null default 'system_generated'
    check (status in ('system_generated', 'admin_adjusted', 'locked')),
  source text not null default 'auto',
  generated_at timestamptz not null default now(),
  generated_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid null references auth.users(id) on delete set null,
  note text null,
  unique (department_id, week_id)
);

create table if not exists public.attendance_roster_snapshot_members (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.attendance_roster_snapshots(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete restrict,
  membership_id uuid null references public.memberships(id) on delete set null,
  legacy_member_directory_id uuid null references public.member_directory(id) on delete set null,
  group_id uuid null references public.groups(id) on delete set null,
  role text null,
  display_name text not null,
  group_name text null,
  attendance_status text null default 'unknown'
    check (attendance_status in ('present', 'late', 'absent', 'unknown')),
  included boolean not null default true,
  source text not null default 'auto_membership'
    check (source in ('auto_membership', 'attendance_snapshot', 'manual_add', 'manual_exclude', 'migration_backfill')),
  reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (snapshot_id, person_id)
);

create table if not exists public.attendance_roster_snapshot_events (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.attendance_roster_snapshots(id) on delete cascade,
  person_id uuid null references public.people(id) on delete set null,
  event_type text not null check (event_type in (
    'snapshot_created',
    'member_added',
    'member_excluded',
    'member_restored',
    'group_changed',
    'role_changed',
    'attendance_status_changed',
    'snapshot_locked',
    'snapshot_unlocked'
  )),
  before jsonb null,
  after jsonb null,
  reason text null,
  created_at timestamptz not null default now(),
  created_by uuid null references auth.users(id) on delete set null
);

create index if not exists idx_attendance_roster_snapshots_week_department
  on public.attendance_roster_snapshots(week_id, department_id);

create index if not exists idx_attendance_roster_snapshot_members_snapshot_included
  on public.attendance_roster_snapshot_members(snapshot_id, included);

create index if not exists idx_attendance_roster_snapshot_members_group
  on public.attendance_roster_snapshot_members(snapshot_id, group_id);

commit;
```

- [x] **Step 2: Add RPC `ensure_attendance_roster_snapshot`**

Append to the same migration:

```sql
create or replace function public.ensure_attendance_roster_snapshot(
  p_department_id uuid,
  p_week_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_snapshot_id uuid;
  v_week_date date;
  v_church_id uuid;
begin
  select w.week_date, d.church_id
    into v_week_date, v_church_id
  from public.weeks w
  join public.departments d on d.id = p_department_id
  where w.id = p_week_id;

  if v_week_date is null then
    raise exception 'week or department not found';
  end if;

  insert into public.attendance_roster_snapshots (
    church_id,
    department_id,
    week_id,
    status,
    source,
    generated_by,
    updated_by
  )
  values (
    v_church_id,
    p_department_id,
    p_week_id,
    'system_generated',
    'auto',
    auth.uid(),
    auth.uid()
  )
  on conflict (department_id, week_id) do update
    set updated_at = public.attendance_roster_snapshots.updated_at
  returning id into v_snapshot_id;

  insert into public.attendance_roster_snapshot_members (
    snapshot_id,
    person_id,
    membership_id,
    legacy_member_directory_id,
    group_id,
    role,
    display_name,
    group_name,
    attendance_status,
    included,
    source
  )
  select distinct on (m.person_id)
    v_snapshot_id,
    m.person_id,
    m.id,
    m.legacy_member_directory_id,
    m.group_id,
    m.role,
    coalesce(md.full_name, p.display_name, '이름 없음') as display_name,
    g.name as group_name,
    'unknown',
    true,
    'auto_membership'
  from public.memberships m
  join public.people p on p.id = m.person_id
  left join public.member_directory md on md.id = m.legacy_member_directory_id
  left join public.groups g on g.id = m.group_id
  where m.department_id = p_department_id
    and m.status = 'active'
    and (m.starts_at is null or m.starts_at::date <= v_week_date)
    and (m.ends_at is null or m.ends_at::date >= v_week_date)
  order by
    m.person_id,
    case when m.role = 'leader' then 0 else 1 end,
    case when m.group_id is not null then 0 else 1 end,
    m.starts_at nulls first
  on conflict (snapshot_id, person_id) do nothing;

  insert into public.attendance_roster_snapshot_events (
    snapshot_id,
    event_type,
    after,
    created_by
  )
  values (
    v_snapshot_id,
    'snapshot_created',
    jsonb_build_object('department_id', p_department_id, 'week_id', p_week_id),
    auth.uid()
  )
  on conflict do nothing;

  return v_snapshot_id;
end;
$$;
```

- [x] **Step 3: Add RPCs for admin edits**

Append:

```sql
create or replace function public.set_attendance_roster_snapshot_member_included(
  p_snapshot_id uuid,
  p_person_id uuid,
  p_included boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_before jsonb;
  v_after jsonb;
begin
  select to_jsonb(m.*) into v_before
  from public.attendance_roster_snapshot_members m
  where m.snapshot_id = p_snapshot_id
    and m.person_id = p_person_id;

  update public.attendance_roster_snapshot_members
     set included = p_included,
         source = case when p_included then source else 'manual_exclude' end,
         reason = p_reason,
         updated_at = now()
   where snapshot_id = p_snapshot_id
     and person_id = p_person_id;

  select to_jsonb(m.*) into v_after
  from public.attendance_roster_snapshot_members m
  where m.snapshot_id = p_snapshot_id
    and m.person_id = p_person_id;

  update public.attendance_roster_snapshots
     set status = 'admin_adjusted',
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_snapshot_id
     and status <> 'locked';

  insert into public.attendance_roster_snapshot_events (
    snapshot_id,
    person_id,
    event_type,
    before,
    after,
    reason,
    created_by
  )
  values (
    p_snapshot_id,
    p_person_id,
    case when p_included then 'member_restored' else 'member_excluded' end,
    v_before,
    v_after,
    p_reason,
    auth.uid()
  );
end;
$$;
```

- [x] **Step 4: Add status update RPC**

Append:

```sql
create or replace function public.set_attendance_roster_snapshot_member_status(
  p_snapshot_id uuid,
  p_person_id uuid,
  p_attendance_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_before jsonb;
  v_after jsonb;
begin
  if p_attendance_status not in ('present', 'late', 'absent', 'unknown') then
    raise exception 'invalid attendance status';
  end if;

  select to_jsonb(m.*) into v_before
  from public.attendance_roster_snapshot_members m
  where m.snapshot_id = p_snapshot_id
    and m.person_id = p_person_id;

  update public.attendance_roster_snapshot_members
     set attendance_status = p_attendance_status,
         updated_at = now()
   where snapshot_id = p_snapshot_id
     and person_id = p_person_id;

  select to_jsonb(m.*) into v_after
  from public.attendance_roster_snapshot_members m
  where m.snapshot_id = p_snapshot_id
    and m.person_id = p_person_id;

  update public.attendance_roster_snapshots
     set status = 'admin_adjusted',
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_snapshot_id
     and status <> 'locked';

  insert into public.attendance_roster_snapshot_events (
    snapshot_id,
    person_id,
    event_type,
    before,
    after,
    reason,
    created_by
  )
  values (
    p_snapshot_id,
    p_person_id,
    'attendance_status_changed',
    v_before,
    v_after,
    p_reason,
    auth.uid()
  );
end;
$$;
```

- [x] **Step 5: Write verification SQL**

Create `supabase/verify_attendance_roster_snapshots_dev_2026-05-08.sql`:

```sql
\set ON_ERROR_STOP on

begin;

select public.ensure_attendance_roster_snapshot(
  'a44bcc65-99ec-4d8d-b029-5fa332bc769e'::uuid,
  '90c803ba-fdf3-4d35-954d-1e58f252c18d'::uuid
) as snapshot_id \gset

select 'snapshot_exists' as check_name, count(*) as actual_count
from public.attendance_roster_snapshots
where id = :'snapshot_id'::uuid;

select 'snapshot_members_unique_people' as check_name,
       count(*) as rows,
       count(distinct person_id) as people
from public.attendance_roster_snapshot_members
where snapshot_id = :'snapshot_id'::uuid;

select public.set_attendance_roster_snapshot_member_status(
  :'snapshot_id'::uuid,
  (
    select person_id
    from public.attendance_roster_snapshot_members
    where snapshot_id = :'snapshot_id'::uuid
    limit 1
  ),
  'present',
  'verify status update'
);

select 'status_update_events' as check_name, count(*) as actual_count
from public.attendance_roster_snapshot_events
where snapshot_id = :'snapshot_id'::uuid
  and event_type = 'attendance_status_changed';

rollback;
```

- [x] **Step 6: Apply migration to dev**

Run:

```bash
docker run --rm -v /ABS/PATH/GraceNote/supabase:/work -e PGPASSWORD='<DEV_DB_PASSWORD>' postgres:16 psql -h <DEV_DB_POOLER_HOST> -p 5432 -U <DEV_DB_USER> -d postgres -f /work/migrations/20260508000000_attendance_roster_snapshots.sql
```

Expected: `CREATE TABLE`, `CREATE FUNCTION`, no errors.

- [ ] **Step 7: Run verification**

Run:

```bash
docker run --rm -v /ABS/PATH/GraceNote/supabase:/work -e PGPASSWORD='<DEV_DB_PASSWORD>' postgres:16 psql -h <DEV_DB_POOLER_HOST> -p 5432 -U <DEV_DB_USER> -d postgres -f /work/verify_attendance_roster_snapshots_dev_2026-05-08.sql
```

Expected:

```text
snapshot_exists actual_count = 1
snapshot_members_unique_people rows = people
status_update_events actual_count = 1
ROLLBACK
```

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260508000000_attendance_roster_snapshots.sql supabase/verify_attendance_roster_snapshots_dev_2026-05-08.sql
git commit -m "db: add attendance roster snapshots"
```

---

## Task 2: Admin Snapshot Helper

**Files:**
- Create: `admin-web/src/lib/attendanceRosterSnapshots.ts`
- Create: `admin-web/src/lib/attendanceRosterSnapshots.test.ts`

- [x] **Step 1: Write pure transformation test**

Create `admin-web/src/lib/attendanceRosterSnapshots.test.ts`:

```ts
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  calculateSnapshotMetrics,
  groupSnapshotMembersForDisplay,
  type AttendanceRosterSnapshotMember,
} from './attendanceRosterSnapshots.ts';

const members: AttendanceRosterSnapshotMember[] = [
  { personId: 'p1', displayName: '김보영', groupName: '동준 상희 조', included: true, attendanceStatus: 'present' },
  { personId: 'p2', displayName: '유성열', groupName: '동준 상희 조', included: true, attendanceStatus: 'unknown' },
  { personId: 'p3', displayName: '박민영', groupName: '새가족조', included: false, attendanceStatus: 'present' },
];

test('snapshot metrics count included people only', () => {
  const metrics = calculateSnapshotMetrics(members);
  assert.deepEqual(metrics, {
    totalPeople: 2,
    presentPeople: 1,
    absentPeople: 1,
    rate: 50,
  });
});

test('group display keeps excluded members out of totals', () => {
  const groups = groupSnapshotMembersForDisplay(members);
  assert.equal(groups[0].name, '동준 상희 조');
  assert.equal(groups[0].totalPeople, 2);
  assert.equal(groups[0].presentPeople, 1);
});
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
cd admin-web
node --test src/lib/attendanceRosterSnapshots.test.ts
```

Expected: fail because module does not exist.

- [x] **Step 3: Create helper**

Create `admin-web/src/lib/attendanceRosterSnapshots.ts`:

```ts
export type AttendanceRosterSnapshotMember = {
  personId: string;
  displayName: string;
  groupId?: string | null;
  groupName?: string | null;
  role?: string | null;
  included: boolean;
  attendanceStatus?: 'present' | 'late' | 'absent' | 'unknown' | null;
};

export type SnapshotAttendanceMetrics = {
  totalPeople: number;
  presentPeople: number;
  absentPeople: number;
  rate: number | null;
};

export const calculateSnapshotMetrics = (
  members: AttendanceRosterSnapshotMember[]
): SnapshotAttendanceMetrics => {
  const included = members.filter((member) => member.included);
  const presentPeople = included.filter((member) =>
    member.attendanceStatus === 'present' || member.attendanceStatus === 'late'
  ).length;

  return {
    totalPeople: included.length,
    presentPeople,
    absentPeople: Math.max(included.length - presentPeople, 0),
    rate: included.length > 0 ? Math.round((presentPeople / included.length) * 100) : null,
  };
};

export const groupSnapshotMembersForDisplay = (
  members: AttendanceRosterSnapshotMember[]
) => {
  const grouped = new Map<string, AttendanceRosterSnapshotMember[]>();

  members.forEach((member) => {
    const key = member.groupName || '조 없음';
    grouped.set(key, [...(grouped.get(key) || []), member]);
  });

  return Array.from(grouped.entries())
    .map(([name, groupMembers]) => {
      const metrics = calculateSnapshotMetrics(groupMembers);
      return {
        name,
        members: groupMembers.sort((a, b) => a.displayName.localeCompare(b.displayName)),
        ...metrics,
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
};
```

- [x] **Step 4: Run test to verify pass**

Run:

```bash
cd admin-web
node --test src/lib/attendanceRosterSnapshots.test.ts
```

Expected: 2 tests pass.

- [x] **Step 5: Add Supabase helper functions**

Append to `attendanceRosterSnapshots.ts`:

```ts
import { supabase } from '@/lib/supabase';

type SnapshotMemberRow = {
  id: string;
  person_id: string;
  display_name: string;
  group_id: string | null;
  group_name: string | null;
  role: string | null;
  included: boolean;
  attendance_status: 'present' | 'late' | 'absent' | 'unknown' | null;
};

export const ensureAttendanceRosterSnapshot = async (
  departmentId: string,
  weekId: string
) => {
  const { data, error } = await supabase.rpc('ensure_attendance_roster_snapshot', {
    p_department_id: departmentId,
    p_week_id: weekId,
  });
  if (error) throw error;
  return String(data);
};

export const fetchAttendanceRosterSnapshotMembers = async (
  snapshotId: string
): Promise<AttendanceRosterSnapshotMember[]> => {
  const { data, error } = await supabase
    .from('attendance_roster_snapshot_members')
    .select('id, person_id, display_name, group_id, group_name, role, included, attendance_status')
    .eq('snapshot_id', snapshotId)
    .order('group_name', { ascending: true })
    .order('display_name', { ascending: true });

  if (error) throw error;

  return ((data || []) as SnapshotMemberRow[]).map((row) => ({
    personId: row.person_id,
    displayName: row.display_name,
    groupId: row.group_id,
    groupName: row.group_name,
    role: row.role,
    included: row.included,
    attendanceStatus: row.attendance_status,
  }));
};
```

- [x] **Step 6: Targeted lint**

Run:

```bash
cd admin-web
npm run lint -- src/lib/attendanceRosterSnapshots.ts
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add admin-web/src/lib/attendanceRosterSnapshots.ts admin-web/src/lib/attendanceRosterSnapshots.test.ts
git commit -m "admin: add attendance roster snapshot helpers"
```

---

## Task 3: Attendance Dashboard Read From Snapshot

**Files:**
- Modify: `admin-web/src/app/attendance/page.tsx`
- Modify: `admin-web/src/lib/attendanceMetrics.ts`
- Test: `admin-web/src/lib/attendanceRosterSnapshots.test.ts`

- [ ] **Step 1: Replace selected week denominator source**

In `admin-web/src/app/attendance/page.tsx`, import:

```ts
import {
  calculateSnapshotMetrics,
  ensureAttendanceRosterSnapshot,
  fetchAttendanceRosterSnapshotMembers,
  groupSnapshotMembersForDisplay,
  type AttendanceRosterSnapshotMember,
} from '@/lib/attendanceRosterSnapshots';
```

- [ ] **Step 2: Add selected snapshot state**

Add near existing selected week state:

```ts
const [selectedSnapshotId, setSelectedSnapshotId] = useState<string | null>(null);
const [snapshotMembers, setSnapshotMembers] = useState<AttendanceRosterSnapshotMember[]>([]);
```

- [ ] **Step 3: Load snapshot in `fetchAttendance()`**

At the start of `fetchAttendance()` after `selectedWeek` is found:

```ts
const snapshotId = await ensureAttendanceRosterSnapshot(selectedDeptId, selectedWeek.id);
setSelectedSnapshotId(snapshotId);
const loadedSnapshotMembers = await fetchAttendanceRosterSnapshotMembers(snapshotId);
setSnapshotMembers(loadedSnapshotMembers);
const snapshotMetrics = calculateSnapshotMetrics(loadedSnapshotMembers);
setSelectedWeekMetrics({
  totalPeople: snapshotMetrics.totalPeople,
  presentPeople: snapshotMetrics.presentPeople,
  absentPeople: snapshotMetrics.absentPeople,
  rate: snapshotMetrics.rate,
  isNoMeetingDay: selectedNoMeetingDateSet.has(selectedWeek.week_date),
  activeWindowPeople: snapshotMetrics.totalPeople,
  snapshotPeople: snapshotMetrics.totalPeople,
  backfilledPeople: 0,
  usedRetroactiveBackfill: false,
});
```

Remove current selected-week metric calculation that uses `calculateWeekAttendanceMetrics()` for the dashboard cards.

- [ ] **Step 4: Use snapshot group display for group stats**

Replace group stats construction with:

```ts
const snapshotGroups = groupSnapshotMembersForDisplay(loadedSnapshotMembers);
setGroupStats(snapshotGroups.map((group) => ({
  name: group.name,
  total: group.totalPeople,
  present: group.presentPeople,
})));
```

- [ ] **Step 5: Keep attendance row detail fallback**

For the first implementation, keep existing `attendanceData` list reconstruction. Do not remove attendance row display logic yet. The snapshot metrics can be correct even while row badges still render from existing `attendanceData`.

- [ ] **Step 6: Run tests**

Run:

```bash
cd admin-web
node --test src/lib/attendanceRosterSnapshots.test.ts src/lib/attendanceMetrics.test.ts
```

Expected: all tests pass.

- [ ] **Step 7: Typecheck**

Run:

```bash
cd admin-web
npx tsc --noEmit --pretty false
```

Expected: no new attendance/snapshot errors. Existing unrelated `src/app/churches/page.tsx(253,81)` may remain.

- [ ] **Step 8: Manual smoke**

User checks:

- 2026년 1월 예닮부 selected week creates snapshot and shows denominator.
- 2026년 2월 1주 no longer jumps to 107 due to current roster backfill.
- 미제출 조 still appears as 0/target if snapshot has members.

- [ ] **Step 9: Commit**

```bash
git add admin-web/src/app/attendance/page.tsx admin-web/src/lib/attendanceMetrics.ts
git commit -m "admin: read attendance metrics from roster snapshots"
```

---

## Task 4: Inline Snapshot Editing UI

**Files:**
- Modify: `admin-web/src/app/attendance/page.tsx`
- Modify: `admin-web/src/lib/attendanceRosterSnapshots.ts`

- [ ] **Step 1: Add snapshot edit helper functions**

Append to `attendanceRosterSnapshots.ts`:

```ts
export const setSnapshotMemberIncluded = async ({
  snapshotId,
  personId,
  included,
  reason,
}: {
  snapshotId: string;
  personId: string;
  included: boolean;
  reason?: string;
}) => {
  const { error } = await supabase.rpc('set_attendance_roster_snapshot_member_included', {
    p_snapshot_id: snapshotId,
    p_person_id: personId,
    p_included: included,
    p_reason: reason || null,
  });
  if (error) throw error;
};

export const setSnapshotMemberStatus = async ({
  snapshotId,
  personId,
  status,
  reason,
}: {
  snapshotId: string;
  personId: string;
  status: 'present' | 'late' | 'absent' | 'unknown';
  reason?: string;
}) => {
  const { error } = await supabase.rpc('set_attendance_roster_snapshot_member_status', {
    p_snapshot_id: snapshotId,
    p_person_id: personId,
    p_attendance_status: status,
    p_reason: reason || null,
  });
  if (error) throw error;
};
```

- [ ] **Step 2: Render snapshot badge section**

In `attendance/page.tsx`, replace the group detail badges with `groupSnapshotMembersForDisplay(snapshotMembers)`.

Badge behavior:

```tsx
<button
  type="button"
  onClick={() => handleToggleSnapshotStatus(member)}
  className={cn(
    'px-4 py-2 rounded-2xl text-sm font-black',
    member.attendanceStatus === 'present' || member.attendanceStatus === 'late'
      ? 'bg-emerald-50 text-emerald-700'
      : member.attendanceStatus === 'absent'
        ? 'bg-slate-100 text-slate-400'
        : 'bg-amber-50 text-amber-700'
  )}
>
  {member.displayName}
</button>
```

- [ ] **Step 3: Add delete/exclude button**

For each badge, add small exclude control:

```tsx
<button
  type="button"
  onClick={() => handleExcludeSnapshotMember(member)}
  className="ml-2 text-slate-400 hover:text-rose-500"
  aria-label={`${member.displayName} 출석 대상 제외`}
>
  ×
</button>
```

- [ ] **Step 4: Add `+` placeholder button**

At end of each group:

```tsx
<button
  type="button"
  onClick={() => setSnapshotAddTargetGroup(group.name)}
  className="px-4 py-2 rounded-2xl border border-dashed border-indigo-300 text-indigo-600 font-black"
>
  +
</button>
```

Initial implementation may open an alert:

```ts
alert('대상 추가 검색 모달은 다음 Task에서 구현합니다.');
```

- [ ] **Step 5: Add status/exclude handlers**

Add:

```ts
const reloadSelectedSnapshot = async (snapshotId: string) => {
  const reloaded = await fetchAttendanceRosterSnapshotMembers(snapshotId);
  setSnapshotMembers(reloaded);
  const metrics = calculateSnapshotMetrics(reloaded);
  setSelectedWeekMetrics((prev) => prev ? {
    ...prev,
    totalPeople: metrics.totalPeople,
    presentPeople: metrics.presentPeople,
    absentPeople: metrics.absentPeople,
    rate: metrics.rate,
  } : prev);
};

const handleExcludeSnapshotMember = async (member: AttendanceRosterSnapshotMember) => {
  if (!selectedSnapshotId) return;
  await setSnapshotMemberIncluded({
    snapshotId: selectedSnapshotId,
    personId: member.personId,
    included: false,
    reason: '관리자 화면에서 출석 대상 제외',
  });
  await reloadSelectedSnapshot(selectedSnapshotId);
};

const handleToggleSnapshotStatus = async (member: AttendanceRosterSnapshotMember) => {
  if (!selectedSnapshotId) return;
  const nextStatus = member.attendanceStatus === 'present' ? 'absent' : 'present';
  await setSnapshotMemberStatus({
    snapshotId: selectedSnapshotId,
    personId: member.personId,
    status: nextStatus,
    reason: '관리자 화면에서 출석 상태 수정',
  });
  await reloadSelectedSnapshot(selectedSnapshotId);
};
```

- [ ] **Step 6: Targeted lint/typecheck**

Run:

```bash
cd admin-web
npm run lint -- src/lib/attendanceRosterSnapshots.ts
npx tsc --noEmit --pretty false
```

Expected: helper lint passes. Typecheck has no new attendance errors.

- [ ] **Step 7: Manual smoke**

User checks:

- Badge click toggles present/absent.
- `×` removes member from selected week denominator only.
- Refresh preserves snapshot edit.
- Actual member/person is not deleted from 성도명부.

- [ ] **Step 8: Commit**

```bash
git add admin-web/src/app/attendance/page.tsx admin-web/src/lib/attendanceRosterSnapshots.ts
git commit -m "admin: edit attendance roster snapshot badges"
```

---

## Task 5: Add Member And Load Group Roster

**Files:**
- Modify: `supabase/migrations/20260508000000_attendance_roster_snapshots.sql`
- Modify: `admin-web/src/lib/attendanceRosterSnapshots.ts`
- Modify: `admin-web/src/app/attendance/page.tsx`

- [ ] **Step 1: Add RPC `add_attendance_roster_snapshot_member`**

Append migration correction or create a follow-up migration if Task 1 has already been applied:

```sql
create or replace function public.add_attendance_roster_snapshot_member(
  p_snapshot_id uuid,
  p_person_id uuid,
  p_group_id uuid default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_person public.people%rowtype;
  v_group_name text;
begin
  select * into v_person from public.people where id = p_person_id;
  select name into v_group_name from public.groups where id = p_group_id;

  insert into public.attendance_roster_snapshot_members (
    snapshot_id,
    person_id,
    group_id,
    display_name,
    group_name,
    included,
    attendance_status,
    source,
    reason
  )
  values (
    p_snapshot_id,
    p_person_id,
    p_group_id,
    coalesce(v_person.display_name, '이름 없음'),
    v_group_name,
    true,
    'unknown',
    'manual_add',
    p_reason
  )
  on conflict (snapshot_id, person_id) do update
    set included = true,
        group_id = excluded.group_id,
        group_name = excluded.group_name,
        source = 'manual_add',
        reason = excluded.reason,
        updated_at = now();
end;
$$;
```

- [ ] **Step 2: Add helper and UI search**

Add helper:

```ts
export const addSnapshotMember = async ({
  snapshotId,
  personId,
  groupId,
  reason,
}: {
  snapshotId: string;
  personId: string;
  groupId?: string | null;
  reason?: string;
}) => {
  const { error } = await supabase.rpc('add_attendance_roster_snapshot_member', {
    p_snapshot_id: snapshotId,
    p_person_id: personId,
    p_group_id: groupId || null,
    p_reason: reason || null,
  });
  if (error) throw error;
};
```

For first UI iteration, add a minimal prompt by person name is not acceptable. Build a modal or reuse existing member search patterns from `MemberModal`. Search must be church/department scoped and person-deduped.

- [ ] **Step 3: Add `조명단 불러오기` RPC**

Create function `load_group_roster_into_attendance_snapshot(p_snapshot_id uuid, p_group_id uuid)` that inserts current active memberships for the group into snapshot with `source='auto_membership'`.

- [ ] **Step 4: Manual smoke**

User checks:

- Unsubmitted group shows `조명단 불러오기`.
- Click adds group members to snapshot.
- Denominator changes immediately.
- Added people survive refresh.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations admin-web/src/lib/attendanceRosterSnapshots.ts admin-web/src/app/attendance/page.tsx
git commit -m "admin: add attendance snapshot roster controls"
```

---

## Task 6: Historical Backfill And Prod Gate

**Files:**
- Create: `supabase/backfill_attendance_roster_snapshots_dev_2026-05-08.sql`
- Modify: `docs/superpowers/plans/2026-05-03-gracenote-phase2-prod-rollout-manifest.md`
- Modify: Notion execution manifest

- [ ] **Step 1: Write dev backfill script**

The script should call `ensure_attendance_roster_snapshot` for:

- 장전제일교회 예닮부 2026-01-01 to 2026-05-31
- Grace Church test departments if needed

It must not write to prod.

- [ ] **Step 2: Run dev backfill**

Run with Docker psql against dev only.

- [ ] **Step 3: Run verification**

Check:

```sql
select week_id, department_id, count(*) people
from public.attendance_roster_snapshots s
join public.attendance_roster_snapshot_members m on m.snapshot_id = s.id
where s.department_id = 'a44bcc65-99ec-4d8d-b029-5fa332bc769e'
group by week_id, department_id
order by week_id;
```

- [ ] **Step 4: User smoke**

User checks:

- January weeks show editable snapshot denominators.
- Unsubmitted groups can be loaded.
- Export uses snapshot denominator.
- UI no longer shows unexplained current-roster backfill text.

- [ ] **Step 5: Update prod manifest**

Add migration candidate and gate:

```text
Attendance snapshot schema/RPC must be applied before attendance dashboard read-switch.
Prod gate: snapshot generation dry-run for one known department/week returns expected rows and no duplicate person rows.
```

- [ ] **Step 6: Commit**

```bash
git add supabase/backfill_attendance_roster_snapshots_dev_2026-05-08.sql docs/superpowers/plans/2026-05-03-gracenote-phase2-prod-rollout-manifest.md
git commit -m "docs: add attendance snapshot rollout gate"
```

---

## Self-Review

Spec coverage:

- Snapshot tables: Task 1.
- Automatic generation: Task 1 RPC.
- Admin edit: Tasks 4 and 5.
- 조명단 불러오기: Task 5.
- Snapshot denominator read: Task 3.
- Historical backfill: Task 6.
- No write-switch for attendance/prayer FK: preserved as non-goal.

Placeholder scan:

- No `TBD` or `TODO` placeholders.
- The plan intentionally leaves full search modal UI details to Task 5 but constrains it to existing `MemberModal` search patterns, church/department scope, and person dedupe.

Type consistency:

- `attendanceStatus` in TypeScript maps from `attendance_status` in SQL.
- `personId` maps from `person_id`.
- `snapshotId` maps to `snapshot_id`.

Risk:

- Task 1 migration changes dev DB. Prod must not be modified.
- Existing `attendance/page.tsx` has lint debt. Use targeted helper lint, typecheck, and manual smoke as gates.
