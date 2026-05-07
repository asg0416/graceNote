# GraceNote Person Structure App/Admin Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move admin-web and Flutter reads toward the Phase 2 person-centered model while keeping legacy write paths safe until attendance/prayer FK migration is explicitly designed.

**Architecture:** Reads move first, writes stay legacy + dual-write until all screens and Edge Functions are verified. Flutter membership/role selection moves to `memberships` first because it only needs group/role metadata and can fall back to `group_members`. Attendance/prayer save remains on legacy IDs in this plan.

**Tech Stack:** Supabase Postgres, Next.js admin-web, Flutter Riverpod, Supabase Dart client, targeted lint/analyze, Phase 2 consistency SQL.

---

## Current State

| Area | State |
| --- | --- |
| Admin member detail | Phase 2 `people/memberships` read enabled |
| Admin member list | Person count and affiliation chips use Phase 2 |
| Admin regrouping | Display/count/export uses Phase 2 person/membership read model |
| Admin dashboard | People count/unassigned count uses active `memberships.person_id` |
| Flutter app | Still mostly reads `group_members/member_directory` |
| Edge Functions | Still reads `group_members/member_directory` |
| Writes | Still legacy writes + dual-write triggers |

## Non-Negotiable Rule

Do not switch attendance/prayer writes directly to `person_id` yet.

Reason:
- `attendance.directory_member_id`
- `attendance.group_member_id`
- `prayer_entries.directory_member_id`
- `prayer_entries.member_id`

These FKs are still part of the current app behavior and historical records. They must be migrated in a separate Phase 3 write-switch plan.

## Execution Order

| Order | Track | Why First / Later |
| --- | --- | --- |
| 1 | Flutter membership/role read-switch | Done. Uses active memberships to decide available groups/roles with legacy fallback. |
| 2 | Flutter group member list read fallback | Attendance screens can display current members via Phase 2 but still save legacy IDs. |
| 3 | Admin attendance read analysis | Admin attendance has real record impact, so analyze before changing. |
| 4 | Edge Function notification target read-switch | No UI, but high operational impact. Needs SQL-equivalent verification. |
| 5 | Prod-safe rollout manifest | Only after app/admin/edge read paths have gates. |
| 6 | Phase 3 write-switch design | Person-centered writes and legacy cleanup. |

---

## Task 1: Flutter `userGroupsProvider` Read-Switch

**Files:**
- Modify: `lib/core/providers/data_providers.dart`
- Test: `dart analyze lib/core/providers/data_providers.dart lib/core/providers/user_role_provider.dart lib/core/models/models.dart`

### Steps

- [x] Add `_fetchUserGroupsFromMemberships(String profileId)` beside `_fetchUserGroups`.

Target query shape:

```dart
final profile = await Supabase.instance.client
    .from('profiles')
    .select('person_id')
    .eq('id', profileId)
    .maybeSingle();

final personId = profile?['person_id'];
if (personId == null) return <Map<String, dynamic>>[];

final response = await Supabase.instance.client
    .from('memberships')
    .select('''
      id,
      group_id,
      role,
      groups(name, church_id, department_id, color_hex, is_new_member_group, climbing_threshold, departments(name, profile_mode))
    ''')
    .eq('person_id', personId)
    .eq('status', 'active')
    .not('group_id', 'is', null)
    .order('starts_at', ascending: false);
```

- [x] Map rows to the existing `UserMembership.fromMap()` shape.

Expected map keys:

```dart
{
  'group_id': row['group_id']?.toString() ?? '',
  'group_name': row['groups']?['name']?.toString() ?? '알 수 없는 조',
  'church_id': row['groups']?['church_id']?.toString() ?? '',
  'department_id': row['groups']?['department_id']?.toString(),
  'color_hex': row['groups']?['color_hex']?.toString() ?? '',
  'department_name': row['groups']?['departments']?['name']?.toString() ?? '부서 미정',
  'profile_mode': row['groups']?['departments']?['profile_mode']?.toString() ?? 'individual',
  'role_in_group': (row['role'] ?? 'member').toString(),
  'is_new_member_group': row['groups']?['is_new_member_group'] ?? false,
  'climbing_threshold': row['groups']?['climbing_threshold'],
  'phase2_membership_id': row['id']?.toString(),
}
```

- [x] Change `_fetchUserGroups(profileId)` to call memberships first and fallback to the existing `group_members` query if memberships returns empty or errors.

Required behavior:

```text
Phase 2 memberships present -> use memberships
Phase 2 error or empty -> use existing group_members path
```

- [x] Keep realtime subscriptions to both `group_members` and `member_directory`, and add a `memberships` stream by `person_id` only if it can be done without breaking null `person_id` users.

For this task, stream-by-person is not added yet. Initial fetch correctness is more important than realtime completeness.

- [x] Run analyze.

Expected:

```bash
dart analyze lib/core/providers/data_providers.dart lib/core/providers/user_role_provider.dart lib/core/models/models.dart
```

Expected output: no errors. Existing style info is acceptable only if unrelated.

Actual:

```bash
HOME=/private/tmp DART_SUPPRESS_ANALYTICS=true dart analyze lib/core/providers/data_providers.dart lib/core/providers/user_role_provider.dart lib/core/models/models.dart
```

Result: No issues found.

- [ ] Manual smoke.

Check:
- 윤영미/이지욱 로그인
- 소속 선택 목록 표시
- 조장/조원 role 정상
- 출석/기도 화면 진입 정상

- [ ] Commit.

```bash
git add lib/core/providers/data_providers.dart docs/superpowers/plans/2026-05-07-gracenote-person-structure-app-admin-migration-plan.md
git commit -m "flutter: prefer memberships for user groups"
```

---

## Task 2: Flutter Group Member List Read Fallback

**Files:**
- Modify: `lib/core/repositories/grace_note_repository.dart`
- Test: `dart analyze lib/core/repositories/grace_note_repository.dart`

### Steps

- [ ] Add a helper to fetch active group member directory rows through Phase 2 memberships.

Target behavior:
- Query `memberships` where `group_id = groupId`, `status = active`.
- Use `legacy_member_directory_id` to fetch `member_directory` rows.
- Keep existing `member_directory.group_name` query as fallback.

- [ ] Ensure returned row shape still contains:

```text
id
full_name
phone
profile_id
group_member_id
role_in_group
family_name
spouse_name
children_info
```

- [ ] Keep attendance/prayer save unchanged.

Do not modify:

```dart
saveAttendanceAndPrayers()
AttendanceModel.directoryMemberId
PrayerEntryModel.directoryMemberId
```

- [ ] Analyze and manual smoke:
- 출석 체크 조원 목록
- 출석 저장/재진입 유지
- 기도 저장/목록 표시

- [ ] Commit.

```bash
git add lib/core/repositories/grace_note_repository.dart
git commit -m "flutter: prefer memberships for group member reads"
```

---

## Task 3: Admin Attendance Read Analysis Before Code

**Files:**
- Read: `admin-web/src/app/attendance/page.tsx`
- Update: this plan and `docs/superpowers/plans/2026-05-03-gracenote-phase2-prod-rollout-manifest.md`

### Steps

- [ ] Identify which queries are display-only and which queries affect saves.
- [ ] Do not change save flow in the same commit.
- [ ] If there is a safe display-only count/list, create a separate implementation task.
- [ ] If display and save are too tightly coupled, mark admin attendance as Phase 3.

Expected decision output:

```text
safe read cleanup now / defer to Phase 3
```

---

## Task 4: Edge Function Read-Switch Plan

**Files:**
- Read: `supabase/functions/notify-event/index.ts`
- Read: `supabase/functions/notify-scheduler/index.ts`
- Read: `supabase/functions/verify-sms/index.ts`
- Update: manifest

### Steps

- [ ] Map each function's current target-selection query.
- [ ] For notification targets, design equivalent `memberships.status='active'` query.
- [ ] Preserve payload shape.
- [ ] Create dev verification SQL or dry-run script before editing production function code.

---

## Task 5: Prod Rollout Gate Consolidation

**Files:**
- Modify: `docs/superpowers/plans/2026-05-03-gracenote-phase2-prod-rollout-manifest.md`
- Modify: Notion “GraceNote Phase 2 운영 반영 최종 실행표 & 이슈 레지스터”

### Steps

- [ ] Add gates for Flutter membership read-switch.
- [ ] Add gates for Flutter group member list read-switch.
- [ ] Add gates for admin attendance decision.
- [ ] Add gates for Edge Function notification target switch.
- [ ] Mark all dev-only auth/SMS helpers as excluded from prod.

---

## Task 6: Phase 3 Write-Switch Design

**Files:**
- Create: `docs/superpowers/plans/YYYY-MM-DD-gracenote-phase3-person-write-switch.md`

### Steps

- [ ] Define target write model for new person/roster/membership writes.
- [ ] Define how `attendance` and `prayer_entries` keep historical links.
- [ ] Decide whether to add `person_id` snapshots to attendance/prayer rows.
- [ ] Decide when legacy `member_directory/group_members` become compatibility views or archives.

---

## Current Next Action

Start Task 1 now.

## Self-Review

Spec coverage:
- Admin-web and Flutter are both included.
- Person-centered reads are separated from write-switch.
- Prod rollout gates are included.
- Flutter smoke is explicitly included.

Placeholder scan:
- No task says “do later” without a concrete owner and file.
- Write-switch is intentionally scoped to Phase 3 because current FK model still depends on legacy IDs.

Risk:
- Flutter app screens still expect legacy IDs. Task 1 and Task 2 preserve output shape and save path to avoid breaking attendance/prayer.
