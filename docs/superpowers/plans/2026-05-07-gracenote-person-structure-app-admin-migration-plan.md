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
| Edge Functions | Notification target reads now prefer `memberships`, with legacy fallback |
| Writes | Member detail/archive/restore and SmartBatch writes use Phase 3 RPCs. Regrouping save RPC is being introduced next. Attendance/prayer saves still use legacy FK paths. |

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
| 2 | Flutter group member list read fallback | Implemented. Attendance screens can display current members via Phase 2 but still save legacy IDs. |
| 3 | Admin attendance read analysis | Admin attendance has real record impact, so analyze before changing. |
| 4 | Edge Function notification target read-switch | Done in code. Needs deployed-function smoke before prod rollout. |
| 5 | Prod-safe rollout manifest | Next. App/admin/edge read paths now need rollout gates. |
| 6 | Phase 3 write-switch design | Person-centered writes and legacy cleanup. |

---

## Role / Permission Conversion Map

Phase 2D에서 역할 처리는 두 종류를 절대 섞지 않는다.

```text
계정 권한 = profiles.role / profiles.is_master / profiles.admin_status
소속 역할 = memberships.role
```

`profiles`는 "이 사용자가 앱/관리자 웹에서 어떤 화면을 볼 수 있는가"를 결정한다.
`memberships`는 "이 사람이 어느 교회/부서/조에서 조장인지 조원인지"를 결정한다.

| Area | Current source | Phase 2D target | Decision |
| --- | --- | --- | --- |
| Admin-web sidebar/header | `profiles.role`, `profiles.is_master`, `profiles.admin_status` | unchanged | 계정 권한이므로 person 구조로 바꾸지 않는다. |
| Admin-web page authorization | `profiles.role`, `profiles.is_master`, `profiles.admin_status` | unchanged | 관리자 승인/마스터 여부는 profiles 기준 유지. |
| Flutter onboarding/login/profile gate | `profiles` | unchanged | 로그인/휴대폰 인증/프로필 완료 여부는 계정 단위. |
| Flutter role tabs/menu | `profiles` + `userGroupsProvider` | `profiles` + active `memberships.role` | 관리자 탭은 profiles, 조장/조원 탭은 memberships 기준. |
| Flutter active group selector | `group_members.role_in_group` fallback | active `memberships.role` first | 완료. fallback 유지. |
| Flutter leader/member screens | active group membership | active `memberships.role` first | read-only 배치에서 smoke 대상. |
| Admin member list/detail affiliations | `member_directory/group_members` | `people/member_profiles/memberships` | 대부분 완료. |
| Admin regrouping display | `member_directory` with Phase 2 overlay | active `memberships` display model | 표시/진단 완료, 저장은 legacy 유지. |
| Admin/Flutter writes | `member_directory/group_members`, attendance/prayer legacy FK | unchanged in Phase 2D | Phase 3 전까지 직접 person write 금지. |
| Edge Functions target roles | `group_members.role_in_group` | active `memberships.role` candidate | admin/Flutter read smoke 이후 진행. |

## Phase 2D Read-Only Batch Checklist

다음 작업은 화면별로 하나씩 끊지 않고 read-only 묶음으로 처리한다.

| Batch | Files / Screens | Work |
| --- | --- | --- |
| Flutter prayer/search read | `prayer_list_screen.dart`, `saved_prayers_screen.dart`, `search_screen.dart`, repository prayer/search methods | 표시용 이름/조/사람 연결을 `person_id/member_profiles/memberships` 기준으로 보강하고 legacy join fallback 유지. |
| Flutter attendance display read | `attendance_dashboard_screen.dart`, `attendance_prayer_screen.dart`, repository attendance methods | 조원 표시와 정렬은 active `memberships` 우선, 저장은 `directory_member_id` 유지. |
| Flutter admin/member display read | `admin_member_detail_screen.dart`, `department_member_directory_screen.dart` | 성도 상세/명부 표시가 legacy row 하나에 묶이지 않도록 person affiliations를 표시. |
| Flutter role/menu smoke | `data_providers.dart`, `user_role_provider.dart`, router role tabs | admin/leader/member/is_master 화면 분기에서 `profiles`와 `memberships.role` 책임 분리 유지. |
| Admin residual read cleanup | `page.tsx`, debug panels | 운영 UI에 남길 정보와 dev-only 진단 UI 분리. |

Read-only batch 완료 기준:

- Flutter 앱에서 admin, leader, member 계정이 각각 올바른 탭/화면을 본다.
- 한 사람이 여러 조/부서 소속이어도 조장 화면과 일반 화면이 active membership 기준으로 동작한다.
- 기도/검색/저장한 기도에서 다른 교회 또는 다른 사람의 데이터가 섞이지 않는다.
- 출석/기도 저장은 기존 legacy FK 방식 그대로 성공한다.
- Admin-web Phase 2 진단 issue 0을 유지한다.

2026-05-09 read-only batch implementation:

- `lib/core/repositories/grace_note_repository.dart`
  - 기도 히스토리 관련 directory row 확장을 legacy `profile_id/name/phone`보다 Phase 2 `member_profiles.person_id` 우선으로 변경.
  - 기도 검색에서 이름 검색 시 같은 person의 모든 legacy directory row를 포함하도록 변경.
  - 저장한 기도/부서 기도 목록/검색 결과에 Phase 2 member profile 정보를 덧씌우되, 기존 `directory_member_id` 저장 구조는 유지.
- `lib/core/providers/data_providers.dart`
  - `userGroupsProvider`가 legacy `group_members`, `member_directory`뿐 아니라 Phase 2 `memberships` 변경도 감지하도록 보강.
  - 계정 권한은 계속 `profiles`, 조장/조원 소속 역할은 active `memberships.role` 우선.
- `admin-web/src/app/page.tsx`
  - 대시보드 최근 가입자/최근 성도 표시를 active `memberships -> people.display_name` 기준으로 전환.
  - Phase 2 read 실패 시 기존 `member_directory` 최근 row fallback 유지.
- `lib/features/home/presentation/screens/member_my_prayer_screen.dart`
  - 앱 "나의 기도" 타임라인 날짜를 `yyyy. M. d.` 형식으로 정리.
  - 같은 person의 과거/현재 조 기도제목에서 Phase 2로 보강된 조 이름이 보이도록 `member`/`member_directory` display alias 동기화.

Verification:

- `HOME=/private/tmp dart analyze lib/core/repositories/grace_note_repository.dart lib/core/providers/data_providers.dart`
  - no errors.
  - existing style-only infos remain in `grace_note_repository.dart`.
- `HOME=/private/tmp dart analyze lib/core/repositories/grace_note_repository.dart lib/core/providers/data_providers.dart lib/features/home/presentation/screens/member_my_prayer_screen.dart`
  - no syntax/type errors from this change.
  - exits with existing warnings in `member_my_prayer_screen.dart` (`unused_field`, `unused_element`, deprecated style warnings).
- `git diff --check`: passed.
- `npm run lint -- src/app/page.tsx`: 0 errors, existing `<img>` warning only.

Smoke to run:

- 조장 계정으로 로그인 후 조장 탭/출석/기도 화면 진입.
- 일반 조원 계정으로 로그인 후 내 기도/기도소식 화면 진입.
- 관리자 계정으로 로그인 후 관리자 화면 진입.
- 기도 검색에서 여러 조에 소속된 사람 이름 검색: 같은 사람의 다른 조 기도도 사람 기준으로 누락 없이 보이는지.
- 저장한 기도에서 이름이 `알 수 없음`으로 깨지지 않는지.
- 기도 히스토리에서 같은 person의 과거/현재 조 기도제목이 같이 보이되 다른 교회 사람이 섞이지 않는지.
- 앱 "나의 기도" 타임라인에서 여러 조 소속 이력의 조 이름이 누락되지 않는지.
- 앱 "나의 기도" 타임라인 날짜가 `2026. 5. 3.`처럼 날짜로만 보이는지.
- 출석/기도 저장은 기존처럼 성공하는지.

2026-05-09 follow-up:

- `lib/features/search/presentation/screens/search_screen.dart`
  - 역할/소속 스코프가 바뀌면 검색 상태를 비우고 `/prayer` 기도소식 화면으로 복귀하도록 변경.
  - 일반 조원은 현재 active membership 조 안에서만 검색하고, 관리자/조장은 넓은 검색을 유지.
- `lib/features/prayer/presentation/screens/prayer_list_screen.dart`
  - 관리자/조장 조별 탭은 선택 주차의 department weekly data를 사용.
  - 기본은 현재 active 조를 계속 표시한다.
  - 삭제/비활성 조는 그 조가 해당 주차에 실제 사용 중이었거나, 해당 주차 기도 기록이 있는 경우에만 표시한다.
- `lib/core/repositories/grace_note_repository.dart`
  - 기도/출석 weekly data에서 삭제/비활성 조의 생성일/종료일을 주차 기준으로 판단.
  - active 조는 주차와 무관하게 기본 표시.
- Smoke:
  - 사용자 확인 완료. 역할 전환 검색 초기화, 삭제 조 생성 전 주차 숨김, 삭제 조 히스토리 노출, 출석 표시 모두 의도대로 동작.
- Commit:
  - `417bada phase2d: refine flutter prayer and attendance reads`

2026-05-12 Phase 3 write-source batch:

- `admin-web/src/app/regrouping/page.tsx`
  - 조편성 저장 화면이 더 이상 groups/member_directory/group_members를 여러 단계로 직접 수정하지 않는다.
  - 저장 payload를 한 번에 `save_regrouping_memberships` RPC로 넘기고, 저장 후 Phase 2 consistency guard만 실행한다.
- `admin-web/src/lib/memberWriteRpc.ts`
  - `saveRegroupingMemberships` RPC wrapper 추가.
- `supabase/migrations/20260512010000_phase3_regrouping_save_rpc.sql`
  - `save_regrouping_memberships` 추가.
  - 기존 `member_directory` row는 사람 정보가 아니라 조편성 필드만 갱신한다.
  - temp 신규 row는 기존 `upsert_member_person_membership`를 사용해 people/member_profiles/memberships와 legacy 호환 row를 같이 만든다.
  - legacy `sync_directory_to_group_members`를 member_directory row 단위로 좁혀, 한 사람이 여러 조에 있을 때 profile 전체 group_members를 꺼버리는 위험을 줄였다.

Verification:

- `save_regrouping_memberships` no-op save rollback test: passed.
- `save_regrouping_memberships` move-one-member rollback test: passed.
- `save_regrouping_memberships` temp-member rollback test: passed.
- `verify_phase2_consistency_summary_dev_2026-05-10.sql`: all 11 checks issue 0.
- `npm run lint -- src/app/regrouping/page.tsx src/lib/memberWriteRpc.ts`: 0 errors, existing regrouping warnings only.
- `git diff --check`: passed.

Smoke to run:

- 조편성에서 기존 성도 1명을 다른 조로 이동 후 저장.
- 신규 조 생성 후 성도 이동/저장.
- 같은 person을 다른 조에 복사 추가 후 저장.
- 같은 person을 같은 조에 중복 배치하면 저장 전 또는 저장 시 차단되는지 확인.
- 조 삭제 후 저장했을 때 해당 조 성도들이 의도대로 비활성/미편성 처리되는지 확인.
- 저장 후 조편성/성도명부 Phase 2 진단 issue 0 유지.

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

- [x] Manual smoke.

Check:
- 윤영미/이지욱 로그인
- 소속 선택 목록 표시
- 조장/조원 role 정상
- 출석/기도 화면 진입 정상

Actual: user confirmed smoke 정상.

- [x] Commit.

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

- [x] Add a helper to fetch active group member directory rows through Phase 2 memberships.

Target behavior:
- Query `memberships` where `group_id = groupId`, `status = active`.
- Use `legacy_member_directory_id` to fetch `member_directory` rows.
- Keep existing `member_directory.group_name` query as fallback.

- [x] Ensure returned row shape still contains:

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

- [x] Keep attendance/prayer save unchanged.

Do not modify:

```dart
saveAttendanceAndPrayers()
AttendanceModel.directoryMemberId
PrayerEntryModel.directoryMemberId
```

- [x] Analyze:
- 출석 체크 조원 목록
- 출석 저장/재진입 유지
- 기도 저장/목록 표시

Actual:

```bash
HOME=/private/tmp DART_SUPPRESS_ANALYTICS=true dart analyze lib/core/repositories/grace_note_repository.dart
```

Result: no errors/warnings, existing style info only.

- [x] Manual smoke:
- 출석 체크 조원 목록이 기존처럼 표시
- 출석 저장/재진입 유지
- 기도 저장/목록 표시

Actual: user confirmed Task 2 smoke 정상.

- [x] Commit.

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

- [x] Identify which queries are display-only and which queries affect saves.
- [x] Do not change save flow in the same commit.
- [x] If there is a safe display-only count/list, create a separate implementation task.
- [ ] If display and save are too tightly coupled, mark admin attendance as Phase 3.

Expected decision output:

```text
safe read cleanup now / defer to Phase 3
```

Actual decision:

```text
safe read cleanup now
```

Reason:
- `admin-web/src/app/attendance/page.tsx` has no insert/update/delete/upsert flow.
- It reads attendance records and current roster data for display, statistics, insights, and export.
- The attendance records themselves still use legacy `attendance.directory_member_id`.
- Therefore the safe change is to read the current roster from active Phase 2 `memberships` first, while preserving legacy `directory_member_id` shape and legacy fallback.

Implementation task:
- [x] Add active-membership roster helper.
- [x] Use helper for current week supplement list, weekly trend denominator, insights roster, and export roster.
- [x] Keep attendance record query and historical snapshot matching by `directory_member_id`.
- [x] Targeted lint/typecheck.
- [x] Phase 2 consistency SQL.
- [ ] Manual smoke.
- [x] Commit.

Actual implementation:
- `fetchAttendanceRoster()` reads active `memberships` first and joins back to active `member_directory` through `legacy_member_directory_id`.
- Legacy `member_directory` read remains as fallback.
- Attendance rows still match by `attendance.directory_member_id`, so historical records and save-compatible shapes are preserved.

Verification:
- `npm run lint -- src/app/attendance/page.tsx`: fails because this file already has broad existing `any`, unused import/state, and hook dependency lint debt. The new helper-specific `any` and new hook warning were removed.
- `npx tsc --noEmit --pretty false`: no error from `attendance/page.tsx`; existing unrelated `src/app/churches/page.tsx(253,81)` error remains.
- `verify_phase2_consistency_dev_2026-04-30.sql`: all mismatch counts 0.

Manual smoke:
- [ ] 출석 현황 화면 로드
- [ ] 주차별 추세/전체 구성원/출석률이 기존과 큰 방향에서 맞음
- [ ] 상세 명단 보기에서 조별 명단 표시
- [ ] 인사이트 리포트/출석 우수자/집중 보살핌 표시
- [ ] 리포트 추출 파일 생성

2026-05-08 smoke findings:
- 출석 현황 화면은 Phase 2 roster를 읽는 smoke 자체는 크게 깨지지 않았다.
- 다만 화면의 기존 계산 모델 결함이 드러났다.
- 예닮부 현재 active membership rows는 112개이고 active people은 107명이다.
- 주차별 화면 총원은 실제 person 수가 바뀌어서가 아니라 `해당 주 attendance snapshot + 미제출 조 current roster supplement`를 섞기 때문에 97~113처럼 흔들린다.
- 김보영은 데이터상 2026-01-31에 첫 `member_directory` row가 생겼고, 동준 상희 조 active row는 2026-02-02에 생겼다. 그래서 1월 리포트에 없거나 2월부터 보이는 것은 현재 dev 데이터 기준으로는 정상이다. 실제 운영 사실과 다르면 시작일/이력 보정이 필요하다.
- 부부 정렬은 attendance page에 구현되어 있지 않다. 현재 roster/export/insight는 `group_name`, `full_name` 중심이라 같은 부부라도 서로 다른 active group row가 있거나 spouse 관계가 cross-group이면 떨어져 보일 수 있다.
- `종합 출석률` 라벨은 실제로 선택 주차의 출석률이다. 라벨을 `선택 주차 출석률` 등으로 바꾸는 것이 맞다.
- 인사이트 리포트와 export의 출석률 계산 기준이 다르다. insight는 `present`만 출석으로 보고 no-meeting day도 분모에 포함한다. export는 `present`와 `late`를 출석으로 보고 no-meeting day를 분모에서 제외한다.

Decision:
- Admin attendance는 단순 read-switch가 아니라 별도 attendance dashboard audit/fix로 분리한다.
- Fix order should be:
  1. 라벨 수정: `종합 출석률` -> `선택 주차 출석률`.
  2. insight/export 출석률 기준 통일: no-meeting day 제외, present+late 출석 인정 여부 확정.
  3. weekly total/card denominator 정책 확정: snapshot total vs current active people/rows를 UI에서 분리.
  4. 부부형 부서 정렬: family/spouse aware sort를 export와 상세 명단에 적용.
  5. 김보영 같은 과거 소속 보정은 코드 문제가 아니라 데이터 이력 보정 후보로 별도 관리.

2026-05-08 implementation:
- Added `admin-web/src/lib/attendanceMetrics.ts`.
- Attendance denominator now uses distinct people by week:
  - people active by `memberships.starts_at/ends_at` on the week date.
  - plus people who have an attendance snapshot row for that week, because historical Phase 2 `starts_at` was reconstructed and may be later than old attendance records.
- For retroactive weeks entered after the fact, selected-week/trend/insight/export metrics can use current active roster backfill:
  - This is needed for cases like January attendance that was entered after the service was introduced in February.
  - Without this, unsubmitted groups disappear from the denominator and the attendance rate looks artificially high.
  - The dashboard now shows a “선택 주차 대상 산정 기준” explanation so the target count change is visible instead of looking like a random bug.
- 2026-05-08 correction:
  - The first backfill rule was too broad. It backfilled current active roster whenever snapshot people exceeded active-window people.
  - That incorrectly made normal weeks like 2026-02-01 jump to current active people count.
  - Correct rule: normal weeks trust week-date active people. Current active roster backfill only applies when the selected week has attendance records but reconstructed active-window people is 0.
  - The explanation panel now also shows week-over-week added/removed people so target count changes explain “who changed,” not just the formula.
- Attendance numerator uses distinct people with `present` or `late`.
- No-meeting days have no denominator/rate.
- The UI label changed from `종합 출석률` to `선택 주차 출석률`.
- Weekly trend, selected-week cards, insight report, and export now share the same metric rules.
- Group ranking now uses each person's actual metric denominator week count instead of blindly using the whole selected period length.
- Export and detailed display sorting now use group first, then spouse/family-aware sort inside the group.

Verification:
- `node --test src/lib/attendanceMetrics.test.ts`: 8 tests passed.
- `npm run lint -- src/lib/attendanceMetrics.ts`: passed.
- `npm run lint -- src/app/attendance/page.tsx`: still fails because of existing broad file lint debt (`any`, unused state/imports, hook dependency warnings). New helper-specific issues were removed.
- `npx tsc --noEmit --pretty false`: no attendance/metrics errors. Existing unrelated `src/app/churches/page.tsx(253,81)` error remains.
- `verify_phase2_consistency_dev_2026-04-30.sql`: all mismatch counts 0.

2026-05-09 snapshot UI/export follow-up:
- The dashboard moved from formula-based denominator repair to explicit `attendance_roster_snapshots` / `attendance_roster_snapshot_members`.
- Admins can adjust a week+department snapshot like an Excel attendance sheet:
  - toggle present/absent by badge click,
  - exclude a person from that week only,
  - add a person to that week only,
  - load one missing group roster,
  - bulk-load all groups that have no included snapshot members.
- Admin web can now set/cancel `no_meeting_days` for a selected week when no leader attendance has been submitted.
- Leader-submitted attendance conflicts are handled as:
  - `덮어쓰기`: apply leader-submitted statuses to the admin snapshot,
  - `병합하기`: add leader-submitted excluded people while keeping existing admin changes,
  - `관리자 화면 유지`: keep the admin snapshot and persist the decision in snapshot member `reason`.
- This persistent reason prevents the same resolved conflict from reappearing after refresh.
- Export now follows the same snapshot source:
  - no-meeting weeks are excluded from rate,
  - snapshot members with `unknown` status export as `X` because they are included in the denominator,
  - `-` means the person was not in that week snapshot,
  - spouse/family-aware sort is applied,
  - if one person has multiple group rows in the same department/week, export merges them by attendance priority: `present` > `late` > `absent/unknown`.

Verification:
- `node --test admin-web/src/lib/attendanceRosterSnapshots.test.ts`: 4 tests passed.
- `git diff --check`: passed.
- `npx tsc --noEmit --pretty false`: no attendance/snapshot errors. Existing unrelated `src/app/churches/page.tsx(253,81)` error remains.
- Manual smoke: user confirmed the updated conflict UI, snapshot edit behavior, report export reflection, no-meeting flow, and multi-group attendance merge direction.

---

## Task 4: Edge Function Read-Switch Plan

**Files:**
- Read: `supabase/functions/notify-event/index.ts`
- Read: `supabase/functions/notify-scheduler/index.ts`
- Read: `supabase/functions/verify-sms/index.ts`
- Update: manifest

### Steps

- [x] Map each function's current target-selection query.
- [x] For notification targets, design equivalent `memberships.status='active'` query.
- [x] Preserve payload shape.
- [x] Add legacy fallback so notification delivery does not depend exclusively on Phase 2 data during rollout.
- [ ] Run deployed dev-function smoke or dry-run after deploy.

Implementation:

- `supabase/functions/notify-event/index.ts`
  - Prayer notification department leaders now read from `memberships.role='leader' AND status='active'` first.
  - Department notice targets now read active profile IDs from `memberships` first.
  - `group_members` remains fallback only.
- `supabase/functions/notify-scheduler/index.ts`
  - Leader reminder targets now read from active `memberships` first.
  - Climbing reminder leader exclusions and recipient leaders now read from active `memberships` first.
  - `group_members` remains fallback only.

Verification:

- `git diff --check`: passed.
- Secret scan for literal Supabase credential patterns: passed.
- `deno fmt/check`: not run locally because `deno` is not installed in the current environment.
- Commit: `4095197 phase2d: read notification targets from memberships`

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

Phase 2D read-switch code is now broadly complete for admin-web, Flutter display reads, and Edge Function notification target reads.

Next:

1. Update prod rollout manifest with exact gates for Phase 2D.
2. Start Phase 3 write-switch design for attendance/prayer/member writes.

## Phase 3 Dev Migration Status

2026-05-10 update:

- Dev Supabase link was switched to `eftdfxmdiefdduksdpwg` for migration execution.
- Remote dev migration history was behind local from `20260502000000` through `20260509000000`.
- Ran `supabase db push --linked --yes` against dev only.
- Applied pending dev migrations through `20260509000000_phase3_attendance_prayer_person_snapshot.sql`.
- `edge_function_base_url not configured in app_config` warnings appeared during push. These are dev notification config warnings, not migration failures.

Verification:

- `verify_phase3_attendance_prayer_person_snapshot_dev_2026-05-09.sql`: all 8 issue counts were `0`.
- `verify_attendance_roster_snapshots_dev_2026-05-08.sql`: passed with test snapshot rollback.
- `verify_p0_hard_delete_guardrails_dev_2026-05-03.sql`: all issue counts were `0`.
- `verify_p0_assignment_scope_and_phone_uniqueness_dev_2026-05-04.sql`: passed.
- `verify_phase2_consistency_dev_2026-04-30.sql`: all mismatch/missing counts were `0` after updating the verification rule to accept `memberships.status='ended'` for inactive legacy group members whose group was soft-ended.

Operational note:

- The local Supabase project link now points to dev, not prod.
- Before any prod operation, explicitly verify `supabase/.temp/project-ref` and avoid relying on implicit linked state.

## Phase 2D Edge Function Dev Smoke

2026-05-10 update:

- Deployed `notify-event` to dev project `eftdfxmdiefdduksdpwg`.
- Deployed `notify-scheduler` to dev project `eftdfxmdiefdduksdpwg`.
- Fixed a schema mismatch found during smoke: Edge Functions were assuming `memberships.profile_id`, but the real Phase 2 model resolves auth profiles through `memberships.person_id -> member_profiles.profile_id`.
- `notify-event` now resolves notification profile targets from active memberships through `member_profiles`, with `group_members` fallback.
- `notify-scheduler` now resolves leader rows from active memberships through `member_profiles`, with `group_members` fallback.
- Stale legacy leader directory IDs whose `member_directory` row no longer exists are ignored in scheduler fallback.

Verification:

- `supabase functions list --project-ref eftdfxmdiefdduksdpwg`: `notify-event` active version `39`, `notify-scheduler` active version `29`.
- `verify_phase2d_edge_notification_targets_dev_2026-05-09.sql`: all mismatch counts were `0`.

Result:

- Phase 2D Edge Function read-switch dev smoke is complete.
- Remaining Phase 2E work should focus on rollout gates and Phase 3 write-switch, not more read-only target discovery.

## Phase 3 Prayer Write-Switch Start

2026-05-10 update:

- First Phase 3 write-switch target is Flutter prayer save.
- `PrayerEntryModel` now supports optional Phase 3 snapshot fields:
  - `person_id`
  - `membership_id`
  - `recorded_group_id`
  - `recorded_department_id`
- `GraceNoteRepository.saveAttendanceAndPrayers()` now enriches prayer payloads before `prayer_entries.upsert`.
- The enrichment resolves the current person/membership snapshot from:
  - `memberships.legacy_member_directory_id`
  - selected `group_id`
  - fallback `member_profiles.member_directory_id`
  - fallback `groups.department_id`
- Existing legacy write keys are preserved:
  - `week_id`
  - `directory_member_id`
  - `member_id`
  - `group_id`
- Attendance save is intentionally unchanged in this step.

Why this matters:

```text
Before:
기도 저장 = legacy directory/profile/group 기준만 명시
DB trigger가 person snapshot을 보정

After:
기도 저장 = 앱 payload가 person/membership/당시 조/부서를 직접 명시
DB trigger는 안전망으로 계속 유지
```

Verification:

- Added `test/core/models/phase3_snapshot_payload_test.dart`.
- RED confirmed first: test failed because `PrayerEntryModel` had no `personId` parameter.
- GREEN confirmed after implementation: `flutter test test/core/models/phase3_snapshot_payload_test.dart` passed.
- `dart analyze lib/core/repositories/grace_note_repository.dart lib/core/models/models.dart test/core/models/phase3_snapshot_payload_test.dart` returned no errors; existing style-only infos remain in `grace_note_repository.dart`.
- `verify_phase3_attendance_prayer_person_snapshot_dev_2026-05-09.sql`: all issue counts were `0`.

Next Phase 3 write-switch target:

- Flutter attendance save should receive the same explicit snapshot treatment.
- After Flutter prayer/attendance writes are both explicit, move to admin-web attendance/manual snapshot writes, then member/regrouping writes.

## Phase 3 Attendance Write-Switch Start

2026-05-10 update:

- Second Phase 3 write-switch target is Flutter attendance save.
- `AttendanceModel` now supports optional Phase 3 snapshot fields:
  - `person_id`
  - `membership_id`
  - `recorded_group_id`
  - `recorded_department_id`
- `GraceNoteRepository.saveAttendanceAndPrayers()` now enriches attendance payloads before `attendance.upsert`.
- The enrichment uses the same resolver as prayer save:
  - `memberships.legacy_member_directory_id`
  - selected `group_id`
  - fallback `member_profiles.member_directory_id`
  - fallback `groups.department_id`
- Existing legacy write keys are preserved:
  - `week_id`
  - `directory_member_id`
  - `group_member_id`
  - `group_id`

Why this matters:

```text
Before:
출석 저장 = legacy directory/group_member/group 기준만 명시
DB trigger가 person snapshot을 보정

After:
출석 저장 = 앱 payload가 person/membership/당시 조/부서를 직접 명시
DB trigger는 안전망으로 계속 유지
```

Verification:

- RED confirmed first: `AttendanceModel serializes phase3 snapshot fields when present` failed because `AttendanceModel` had no `personId` parameter.
- GREEN confirmed after implementation: `flutter test test/core/models/phase3_snapshot_payload_test.dart` passed.
- `dart analyze lib/core/repositories/grace_note_repository.dart lib/core/models/models.dart test/core/models/phase3_snapshot_payload_test.dart` returned no errors; existing style-only infos remain in `grace_note_repository.dart`.
- `verify_phase3_attendance_prayer_person_snapshot_dev_2026-05-09.sql`: all issue counts were `0`.

Next Phase 3 write-switch target:

- Admin-web attendance/manual roster snapshot writes.
- Then admin member/regrouping writes.

## Phase 2/3 Write-Flow Gate

2026-05-10 update:

- Added `supabase/verify_phase2_consistency_summary_dev_2026-05-10.sql`.
- Purpose:
  - The older Phase 2 verification file is useful in `psql`, but `supabase db query` only prints the last result set.
  - This summary gate returns one table with `check_name` and `issue_count`, so it can be used quickly before/after admin-web member/regrouping writes.
- Current dev result:
  - All `issue_count` values were `0`.

What this means:

```text
성도 추가/수정/조편성 저장은 아직 legacy 테이블에 쓰지만,
그 결과가 people/member_profiles/memberships로 정상 동기화되는지
한 번에 확인할 수 있는 운영 전용 gate를 추가했다.
```

Use this before production rollout:

```bash
supabase db query --linked -f supabase/verify_phase2_consistency_summary_dev_2026-05-10.sql -o table
```

## Admin-Web Phase 2 Write Guard

2026-05-10 update:

- Added `admin-web/src/lib/phase2WriteGuards.ts`.
- Applied the guard after these legacy writes:
  - `MemberModal`: single member add/edit
  - `SmartBatchModal`: AI/bulk member registration
  - `members/page.tsx`: move, archive, undo, group rename directory sync
  - `regrouping/page.tsx`: regrouping save, duplicate deactivation, copied member insert

Why this matters:

```text
현재 성도/조편성 저장은 아직 member_directory/group_members에 쓴다.
DB trigger가 people/member_profiles/memberships를 동기화한다.

문제는 trigger 누락이 생기면 화면상 저장은 성공처럼 보일 수 있다는 점이다.
이 guard는 저장 직후 member_profiles/memberships가 만들어졌는지 확인해서
누락이면 사용자에게 바로 오류를 보여준다.
```

This is not the final write-switch yet.

- It does not remove legacy writes.
- It makes the current legacy-write + Phase-2-sync bridge safer.
- Final source-of-truth switch still belongs to the next Phase 3 member/regrouping write-switch batch.

Verification:

- `npm run lint -- src/lib/phase2WriteGuards.ts src/components/MemberModal.tsx src/components/SmartBatchModal.tsx src/app/regrouping/page.tsx src/app/members/page.tsx`
  - 0 errors.
  - Existing warnings remain in `members/page.tsx`, `regrouping/page.tsx`, `MemberModal.tsx`.
- `git diff --check`: passed.
- `verify_phase2_consistency_summary_dev_2026-05-10.sql`: all issue counts were `0`.

## Flutter Phase 2 Write Guard

2026-05-10 update:

- Added the same post-write Phase 2 sync guard to Flutter repository member writes:
  - `addDirectoryMember`
  - `updateDirectoryMember`
  - `toggleMemberActivation`
  - `deleteDirectoryMember`

Why this matters:

```text
Flutter 관리자/명부 화면에서도 아직 member_directory에 쓴다.
저장 직후 member_profiles/memberships 생성 여부를 확인해서
Phase 2 person 구조가 누락된 채로 넘어가지 않게 한다.
```

Verification:

- `dart analyze lib/core/repositories/grace_note_repository.dart`
  - no errors.
  - existing style-only infos remain in `grace_note_repository.dart`.
- `git diff --check`: passed.

## Phase 3 Member Write RPC

2026-05-11 update:

- Added a person-centered member write RPC:
  - `supabase/migrations/20260511000000_phase3_member_write_rpc.sql`
  - `supabase/migrations/20260511001000_phase3_member_write_rpc_upsert_fix.sql`
- Switched these member add/edit paths to call the RPC:
  - `admin-web/src/components/MemberModal.tsx`
  - `admin-web/src/components/SmartBatchModal.tsx`
  - `lib/core/repositories/grace_note_repository.dart`
- Added admin-web RPC wrapper:
  - `admin-web/src/lib/memberWriteRpc.ts`

Meaning in plain terms:

```text
이전: 화면이 member_directory에 직접 저장하고, DB trigger가 사람 구조를 따라잡는다.
이제: 화면이 "이 사람/이 소속을 저장해줘"라고 RPC에 요청한다.
RPC가 people/person/member_directory 호환 row를 한 번에 맞춘다.

member_directory는 아직 사라진 것이 아니다.
출석/기도/기존 화면 호환을 위해 당분간 같이 저장되는 compatibility row다.
```

Scope decision:

- Single member add/edit and SmartBatch add/edit are included.
- Flutter member add/edit is included.
- Regrouping save is not included yet because it changes many rows and group lifecycle together.
- Activation/deactivation lifecycle RPC is the next member write batch.

Verification status:

- Admin-web targeted lint: 0 errors, existing `MemberModal.tsx` warning remains.
- Flutter repository analyze: 0 errors, existing style-only infos remain.
- `git diff --check`: passed.
- Dev DB migration apply: passed on dev project `eftdfxmdiefdduksdpwg`.
- Phase 2 summary gate: all issue counts `0`.
- Phase 3 attendance/prayer snapshot gate: all issue counts `0`.

## Phase 3 Member Lifecycle RPC

2026-05-11 update:

- Added `set_member_directory_active_status(...)`.
- Switched these active/inactive write paths to the lifecycle RPC:
  - `admin-web/src/app/members/page.tsx`: single inactive, bulk inactive, undo restore
  - `admin-web/src/app/members/[id]/page.tsx`: active/inactive toggle
  - `lib/core/repositories/grace_note_repository.dart`: `toggleMemberActivation`, `deleteDirectoryMember`
- Also routed member detail profile/family edits through the existing member write RPC.

Meaning in plain terms:

```text
성도 추가/수정뿐 아니라 "활성/비활성" 상태 변경도 이제 DB RPC가 담당한다.
화면은 여전히 member_directory id로 요청하지만, DB 안에서는 memberships 상태와
기존 출석/기도 기록 보존 원칙을 함께 맞춘다.
```

Still deferred:

- Regrouping save source-of-truth conversion.
- Group lifecycle source-of-truth RPC.
- Final removal of legacy `member_directory` / `group_members`.

Verification:

- Dev DB migration apply: passed on dev project `eftdfxmdiefdduksdpwg`.
- Phase 2 summary gate: all issue counts `0`.
- Phase 3 attendance/prayer snapshot gate: all issue counts `0`.
- Admin-web targeted lint: 0 errors; existing warnings remain in `members/page.tsx`.
- Flutter repository analyze: 0 errors; existing style-only infos remain.

2026-05-12 update:

- Corrected the lifecycle model from single `member_directory` row activation to person-in-department activation.
- Added `set_person_department_active_status(...)`.
- Added a follow-up RPC fix so department-only/unassigned memberships can also be restored, not only group-linked rows.
- Admin-web member list/detail inactive/restore actions now target a person within a department:
  - If the same person belongs to multiple groups in that department, all active group memberships are archived together.
  - Restore reactivates the latest archived membership set for that person in that department.
  - Memberships in other departments/churches are not touched.
- Added admin-web `/archive` page under the church operations menu:
  - inactive member department affiliations
  - inactive departments
  - inactive groups
  - restore actions for each category
- Archive member restore also falls back through `member_profiles` when older `member_directory.person_id` is empty.

Verification:

- Dev DB migration apply: first lifecycle migration applied; follow-up RPC fix is pending because Supabase pooler temp-role auth circuit breaker is blocking new DB connections.
- Phase 2 summary gate: all issue counts `0`.
- Phase 3 attendance/prayer snapshot gate: blocked by Supabase temp-role pooler auth circuit breaker, not by SQL/code output.
- Admin-web targeted lint: 0 errors; existing warnings remain in `members/page.tsx` and `Sidebar.tsx`.
- Flutter repository analyze: 0 errors; existing style-only infos remain.
- Token temp file was removed after DB work.

2026-05-12 restore debugging update:

- 김보영 복구 실패로 person-in-department restore RPC를 실제 데이터 기준으로 재진단했다.
- Root cause:
  - Restore branch에서 `member_directory.is_active=false`를 다시 업데이트하면서 기존 legacy sync trigger가 실행됐다.
  - 그 trigger가 방금 `active`로 바꾼 `memberships`를 다시 `inactive`로 되돌렸다.
  - 이후 재호출에서는 같은 조 duplicate membership 중 방금 업데이트된 오래된 row가 canonical로 선택되어 legacy unique assignment 충돌이 났다.
- Final restore rule:
  - Phase 2 `memberships`가 소속의 기준이다.
  - 같은 person+department 안에서 서로 다른 active group은 모두 복구한다.
  - 같은 person+department+group 중복 active membership은 하나만 남긴다.
  - 이미 active인 legacy `member_directory` row를 우선 canonical로 선택한다.
  - inactive duplicate legacy row는 이력으로 남기되 휴지통에는 active affiliation이 있으면 표시하지 않는다.
- Dev DB verification:
  - 김보영 예닮부 복구 후 active memberships: `Re-born(새가족부)❤️`, `동준 상희 조`
  - duplicate Re-born membership 1건은 inactive history로 보존
  - active group_members: 2
  - active legacy directory rows: 2
 - Phase 2 summary gate: all issue counts `0`

2026-05-12 selected restore update:

- Person-in-department restore no longer means “turn every historical membership back on.”
- Added `person_department_lifecycle_events`:
  - `archive` event records the exact person/church/department deactivation batch.
  - archived `memberships` now point to `archived_by_event_id`.
  - restore events record selected group ids and point back to the latest archive event when available.
- Added selected restore RPC:
  - `restore_person_department_affiliation(person_id, church_id, department_id, group_ids)`
  - If `group_ids` is provided, only those groups are restored.
  - If `group_ids` is empty, the person is restored as department-only/unassigned.
  - Old restore behavior is kept only as fallback for callers that do not pass group ids.
- Archive UI now shows restore group chips:
  - default selection is the latest archived batch, not all historical groups.
  - admin can uncheck groups before restore.
  - old group history remains inactive/ended and is not lost.
- Verification:
  - Targeted admin-web lint: passed for `archive/page.tsx` and `memberWriteRpc.ts`.
  - Dev DB migration apply: passed.
  - Transactional selected-restore test: archived a multi-group person, restored one selected group, verified only one active group returned, then rolled back.
  - Phase 2 summary gate: all issue counts `0`.

2026-05-14 Phase 3 member write cleanup:

- Admin-web 성도 write 경로 중 직접 `member_directory`를 수정하던 잔여 경로를 RPC 경유로 전환했다.
- Converted paths:
  - `admin-web/src/app/members/page.tsx`
    - bulk move
    - bulk move undo
    - group rename compatibility sync
  - `admin-web/src/app/members/[id]/page.tsx`
    - detail memo/profile field save
    - account link save
  - `admin-web/src/app/departments/page.tsx`
    - group rename compatibility sync
- Flutter 조장 성도 추가/수정/삭제 경로는 이미 `GraceNoteRepository`의 `upsert_member_person_membership` / active-status RPC를 사용하고 있음을 확인했다.
- Direct legacy member write scan:
  - no remaining direct `member_directory.update`
  - no remaining direct `group_members.insert/update/delete`
- Remaining intentional legacy-FK write paths:
  - `attendance` save/upsert still uses `directory_member_id` / `group_member_id`.
  - `prayer_entries` save/update still uses legacy member FK fields plus Phase 3 snapshot fields.
  - `profiles` writes remain account/permission writes, not person membership writes.
  - `groups` / `departments` writes remain organization lifecycle writes; member compatibility effects must go through RPC where they touch member affiliation.
- Verification:
  - `npm run lint -- src/app/members/page.tsx 'src/app/members/[id]/page.tsx'`: 0 errors, existing warnings in `members/page.tsx`.
  - `npm run lint -- src/components/RichTextEditor.tsx`: 0 errors.
  - `npm run lint -- src/app/departments/page.tsx`: 0 errors, existing hook dependency warning.
  - Flutter targeted `dart analyze` on member write/read files: no new type errors; existing style warnings remain.
  - Phase 2 consistency summary gate: all checks `0`.
  - changed-file secret scan: no matches.

Next Phase 3 write-switch boundary:

- Do not remove legacy FK columns yet.
- Next schema-level work should be attendance/prayer write model design:
  - keep legacy IDs for historical compatibility,
  - make `person_id`, `membership_id`, `group_id`, and display snapshots explicit,
  - define backfill and report behavior before changing app save semantics.

2026-05-15 Admin attendance snapshot integrity gate:

- Admin attendance dashboard uses `attendance_roster_snapshots` and `attendance_roster_snapshot_members` as the administrator-confirmed attendance roster source.
- This is intentionally separate from leader-submitted `attendance` rows:
  - leader app submissions keep writing `attendance` with legacy FK columns plus Phase 3 snapshot fields,
  - admin dashboard corrections update roster snapshot members,
  - reports use snapshot members as the denominator/source of confirmed roster truth.
- Added `supabase/verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`.
- The gate checks:
  - every snapshot member points to an existing `people` row,
  - person church matches snapshot church,
  - membership person/church/department matches the snapshot member,
  - group church/department matches the snapshot,
  - legacy directory row does not point to a different person or department,
  - included members have display names,
  - snapshot/person duplicates do not exist.
- Dev result:
  - all 9 checks returned `issue_count = 0`.
- Next write-switch boundary:
  - Do not merge admin snapshot edits into leader-submitted `attendance` rows automatically.
  - Before changing that policy, design explicit conflict semantics for "admin confirmed roster" vs "leader submitted attendance".

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

## 2026-05-15 Fresh Migration Dry-Run

Context:
- Local `dev` was aligned to `origin/dev` after integrating the person-structure branch on top of remote UI/autosave changes.
- Safety branch: `backup/dev-before-origin-merge-20260515`.

Result:
- `supabase db reset` on local fresh DB completed successfully.
- Migrations applied through `20260515001000_app_config_rls.sql`.
- This validates that the current migration chain can build a new database from scratch without relying on manual dev DB drift.

Fresh local gates:
- `verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql`: all issue counts `0`.
- `verify_phase2_consistency_summary_dev_2026-05-10.sql`: all issue counts `0`.
- `verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql`: all issue counts `0`.
- `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`: all issue counts `0`.
- `verify_app_config_rls_dev_2026-05-15.sql`: all issue counts `0`.

Verification cleanup:
- `verify_phase3_attendance_prayer_person_snapshot_dev_2026-05-09.sql` still contains optional diagnostic SELECTs, so `supabase db query --file` can fail with multiple-command prepared statement errors.
- Added single-statement summary gate: `supabase/verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql`.
- `verify_phase2_people_memberships_schema_dev_2026-04-30.sql` still uses psql meta commands.
- Added single-statement summary gate: `supabase/verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql`.

Security note:
- Supabase CLI advisory previously reported `public.app_config` with RLS disabled.
- Added `20260515001000_app_config_rls.sql`.
- Policy shape: service_role full access; anon/authenticated can only read `edge_function_base_url`.

## 2026-05-15 Admin UI Rollout Polish

Scope:
- This batch is UI/operational polish on top of the person-structure migration.
- It does not change the core Phase 2/3 database source-of-truth rule.

Changes:
- 성도 상세:
  - 현재 소속, 소속 이력, 가족 정보를 운영자가 보기 쉬운 카드 구조로 정리.
  - 긴 소속 이력은 화면을 과도하게 밀지 않도록 축약/스크롤 형태로 정리.
- 성도 명부:
  - 소속 정보 칩을 과하게 펼치지 않고 대표 소속 + 추가 소속 hover card로 정리.
  - 이름 옆 role 표시와 소속 칩의 조장 표시가 중복되지 않도록 정리.
- 조편성 관리:
  - Phase 2 조편성 진단은 정상 상태에서 운영 UI를 과하게 차지하지 않도록 정리.
  - profile-less/directory-only 케이스도 조편성 화면과 성도명부가 같은 active 소속을 보도록 보정.
- 비활성 관리:
  - “휴지통” 표현을 사용자 친화적인 비활성 관리 메뉴로 변경.
  - person+department 단위 비활성/복구 흐름을 유지하고, 복구 시 사용자가 되살릴 조를 선택할 수 있게 함.
- 출석 현황:
  - `주차별 출석`과 `인사이트 리포트`를 탭으로 분리.
  - 주차별 탭에는 교회/부서/연월/주차 필터를 유지.
  - 인사이트 탭에서는 상단 주차 필터바를 숨기고, 화면 안에 현재 분석 대상 교회/부서/기간을 명시.
  - 리포트 추출, 지난 주와 달라진 출석 대상, 모임없는 날 UI를 사이드 액션으로 정리.
  - 출석 기록이 있는 주차는 모임없는 날 지정 버튼을 비활성화.

Insight calculation decision:
- 사람별 출석률:
  - 선택 기간의 공통 모임 주차 수를 분모로 사용한다.
  - 출석/지각은 출석으로 인정한다.
  - 모임없는 날은 분모에서 제외한다.
- 조별 출석 순위:
  - 분자: 선택 기간 동안 해당 조에서 출석/지각 처리된 person-week 누적 수.
  - 분모: 선택 기간 동안 해당 조 snapshot에 포함된 person-week 누적 수.
  - UI의 주요 표시는 공통 모임 주차 기준 평균 출석 인원 / 평균 대상 인원으로 보여준다.
  - 기간 누적값은 보조 정보로만 표시한다.
  - 특정 조가 일부 주차에만 snapshot 데이터가 있으면 `n주 데이터`로 보조 표시한다.

Verification:
- User smoke confirmed no blocking issues after UI polish.
- `git diff --check`: passed.
- `npx eslint src/app/attendance/page.tsx`: 0 errors; existing hook dependency warnings remain.

Operational note:
- Attendance insights are report-style summaries, not authoritative accounting tables.
- The authoritative denominator for admin reports remains `attendance_roster_snapshots` / `attendance_roster_snapshot_members`.
- Any future change that merges admin snapshots into leader-submitted `attendance` rows needs a separate conflict policy.

## 2026-05-19 Regrouping Effective Week Plan

Problem:
- Church regrouping is usually applied from a specific worship week, not from the timestamp when an admin saves the screen.
- Example: an admin may save the new July arrangement in May, or may backfill an arrangement that started operating in the field two weeks ago.
- Using `groups.created_at` / save time as the operating period makes app prayer tabs and attendance screens show the wrong groups for historical weeks.

Decision:
- Treat regrouping changes as period-based membership changes.
- 1차 implementation supports current/past effective weeks only.
- Future scheduled arrangements require a separate draft/season table so live app screens are not changed before the effective week.

1차 implementation:
- Add a 5-parameter overload of `save_regrouping_memberships` with `p_effective_week_date`.
- Keep the existing 4-parameter RPC for compatibility.
- Admin regrouping save passes the selected effective week.
- Newly created groups get `groups.active_from = p_effective_week_date`.
- Groups removed by that save get `groups.ended_at = p_effective_week_date - 1 second`.
- Just-ended `member_directory.left_at` and `memberships.ends_at` are corrected to the effective boundary.
- Active memberships saved in the regrouping batch have `starts_at` corrected back to the effective week when needed.

Admin UI:
- Add an `적용 주차` selector to 조편성 관리.
- Dates are snapped to the Sunday of that week.
- Future dates are intentionally blocked in 1차 because the current save path still writes live compatibility rows.

2차 required for true future scheduling:
- Add `regrouping_seasons` or `regrouping_drafts` tables.
- Store future groups/assignments separately from live `groups/member_directory/group_members`.
- Let admins edit scheduled seasons until activation.
- On/after effective week, apply the draft to live groups/memberships in one controlled transition.
- Allow archived/current group operating periods to be corrected from a management UI when needed.

Smoke:
- Save a regrouping with `적용 주차 = 2026-05-17`.
- A removed old group should still appear before 2026-05-17 if it existed then.
- That old group should not appear from 2026-05-17 onward unless it has actual historical records in that selected week.
- A newly created group should appear from 2026-05-17 onward, not before.
- App 기도소식 tabs, admin 출석현황, and member detail prayer timeline should agree on group names for the same selected week.

## 2026-05-23 Regrouping Seasons Direction

The 1st-stage `effective_week_date` implementation is useful for current/past correction, but it is not the final UX for future church regrouping.

Decision:
- Stop treating the temporary effective-week UI as the main smoke target.
- Move the final feature toward a season/draft/apply model.
- Future regrouping drafts must not mutate live `groups`, `member_directory`, `group_members`, or `memberships` before the effective week.
- Normal Flutter prayer/attendance and admin attendance screens should continue reading live/snapshot group state, not draft rows.
- Applying a season should be one controlled transaction that writes live memberships and legacy compatibility rows.

Design document:
- `docs/superpowers/specs/2026-05-23-regrouping-seasons-design.md`

Implementation direction:
1. Add additive `regrouping_seasons`, `regrouping_plan_groups`, and `regrouping_plan_assignments` tables.
2. Add draft create/save RPCs that write only plan tables.
3. Convert admin regrouping to season-first UX.
4. Add `apply_regrouping_season` RPC after draft save/read is stable.
5. Keep the existing `save_regrouping_memberships(..., p_effective_week_date)` path for past/current correction only.

Progress:
- 2026-05-23: Additive season schema migration created and applied to dev DB (`eftdfxmdiefdduksdpwg`) through Docker psql without printing DB URL.
- 2026-05-23: Schema verifier passed: tables 3/3, indexes 9/9, RLS 3/3, policies 6/6.
- 2026-05-23: Draft RPC migration created and applied to dev DB through Docker psql.
- 2026-05-23: Draft verifier passed: draft function count 2/2, created season returned 1, plan group count 1, assignment count 1, live `groups/member_directory/group_members/memberships` counts unchanged 1.
- 2026-05-23: Draft RPC plan group ID handling fixed. Plan rows no longer reuse live `groups.id`, so the same source group can appear in multiple future seasons without primary-key collision.
- 2026-05-23: Multi-season verifier passed: two seasons for one source group produce 2 distinct plan group IDs and 1 distinct source group ID.
- 2026-05-23: Admin-web `regroupingSeasonsRpc` wrapper added with Node test coverage for create/save/apply RPC payloads and error propagation.
- 2026-05-23: RPC wrapper verification passed: `node --test admin-web/src/lib/regroupingSeasonsRpc.test.ts`, targeted admin-web lint, and `npx tsc --noEmit --pretty false`.
- 2026-05-23: Admin regrouping page now has separate `시즌 초안` and `현재/과거 보정` modes. Season draft save calls only `create_regrouping_season` / `save_regrouping_season_draft`; live correction save is disabled in season mode.
- 2026-05-23: Regrouping season payload helpers added and tested so temp group IDs are preserved for RPC mapping while live source group IDs remain separate.
- 2026-05-23: `apply_regrouping_season` RPC added and applied to dev DB. It rejects future effective weeks so drafts do not mutate live data before the target week.
- 2026-05-23: Apply verifier passed in rollback: season applied 1, active membership from effective week 1, planned rows preserved 1, created group active_from effective week 1.
- 2026-05-23: Admin regrouping page apply button connected. It is enabled after a season draft is saved and calls `apply_regrouping_season`.
- 2026-05-23: Admin regrouping page can now list saved season drafts for the selected church/department and reopen a draft into the Kanban board without touching live rows.
- 2026-05-23: Season controls now show applied/future/current status. Applied seasons cannot be edited or re-applied, and future seasons cannot be applied before the effective week.
- 2026-05-23: Future draft safety verifier passed on dev: future draft save leaves live counts unchanged 1 and future apply rejection 1.
- 2026-05-23: Admin regrouping toolbar now separates `시즌 초안` actions from `현재/과거 보정` actions. Season mode no longer shows the live correction week/save control, and explicitly states that drafts do not affect app/attendance/prayer until applied.
- 2026-05-23: Applied season boards are now read-only at the Kanban interaction level. Drag/drop, group edit, group delete, member add, leader toggle, and member remove controls are disabled after a season is applied.
- 2026-05-23: Added `node scripts/verify-regrouping-season-boundary.mjs` to guard that regrouping season draft tables/RPCs are not referenced from Flutter/admin operational screens. This keeps future drafts out of high-traffic app/attendance/prayer read paths.
- 2026-05-23: Added `update_regrouping_season` RPC so saved draft title/effective week changes persist. Admin season save now updates metadata before saving plan rows. Dev rollback verifiers still pass for schema, future draft safety, current-week apply, and preprod gates.
- Next: run end-to-end smoke on dev for future draft save, reopen, blocked early apply, and current-week apply.
