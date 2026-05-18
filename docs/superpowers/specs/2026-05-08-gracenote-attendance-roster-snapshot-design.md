# GraceNote Attendance Roster Snapshot Design

## Purpose

출석률 분모를 매번 현재 명부나 출석 제출 기록에서 추론하지 않고, 주차별 출석 대상 명단을 snapshot으로 저장한다.

현재 문제는 다음과 같다.

- `memberships.starts_at/ends_at` 기준으로 계산하면 과거에 실제로 있었던 사람이 빠질 수 있다.
- `attendance` 기록에 등장한 사람을 보정으로 더하면 제출한 조만 분모에 반영될 수 있다.
- 현재 active roster 전체를 보정으로 더하면 2월 정상 주차까지 현재 인원으로 부풀어 오른다.
- 운영자는 “왜 92명에서 102명이 됐는지”를 계산식보다 실제 사람 변화로 이해해야 한다.

목표는 엑셀 출석표와 비슷한 운영 경험을 만드는 것이다.

```text
그 주 출석 대상 명단이 먼저 있다.
출석률 분모는 그 명단의 실제 사람 수다.
틀린 명단만 관리자가 고친다.
```

## Core Decision

주차별 출석 대상 명단을 별도 snapshot으로 저장한다.

관리자가 매주 확정 버튼을 누르지는 않는다. 시스템이 필요 시 자동 생성한다. 다만 과거 주차나 특수 케이스에서 명단이 틀리면 부서 관리자 이상이 직접 수정할 수 있다.

권한:

- 마스터: 모든 교회/부서 snapshot 수정 가능
- 교회 관리자: 해당 교회 snapshot 수정 가능
- 부서 관리자: 담당 부서 snapshot 수정 가능
- 조장: 출석 제출 가능, snapshot 분모 수정 불가

## Proposed Tables

### `attendance_roster_snapshots`

주차 + 부서 단위 snapshot header.

```sql
attendance_roster_snapshots
- id uuid primary key
- church_id uuid not null references churches(id)
- department_id uuid not null references departments(id)
- week_id uuid not null references weeks(id)
- status text not null default 'system_generated'
- source text not null default 'auto'
- generated_at timestamptz not null default now()
- generated_by uuid null references auth.users(id)
- updated_at timestamptz not null default now()
- updated_by uuid null references auth.users(id)
- note text null
```

Unique:

```sql
unique (department_id, week_id)
```

Status values:

- `system_generated`: 시스템이 만든 기본 명단
- `admin_adjusted`: 관리자가 수정한 명단
- `locked`: 운영자가 더 이상 바꾸지 않도록 잠근 명단

### `attendance_roster_snapshot_members`

snapshot에 포함되는 실제 사람 목록.

```sql
attendance_roster_snapshot_members
- id uuid primary key
- snapshot_id uuid not null references attendance_roster_snapshots(id)
- person_id uuid not null references people(id)
- membership_id uuid null references memberships(id)
- legacy_member_directory_id uuid null references member_directory(id)
- group_id uuid null references groups(id)
- role text null
- display_name text not null
- group_name text null
- attendance_status text null
- included boolean not null default true
- source text not null default 'auto_membership'
- reason text null
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()
```

Unique:

```sql
unique (snapshot_id, person_id)
```

Source values:

- `auto_membership`: 주차 기준 active membership에서 자동 생성
- `attendance_snapshot`: 출석 기록에는 있지만 active membership에는 없어서 자동 보강
- `manual_add`: 관리자가 직접 추가
- `manual_exclude`: 관리자가 직접 제외
- `migration_backfill`: 과거 데이터 backfill 중 생성

`included=false` row는 삭제하지 않는다. 관리자가 그 주차 대상에서 제외한 이력을 남기기 위해 사용한다.

`attendance_status`는 그 주차 snapshot에서 관리자가 보는 출석 상태 캐시다. 실제 출석 저장은 기존 `attendance` 테이블과 호환되어야 하므로 초기에는 `attendance` row와 동기화해서 사용한다.

허용 값:

- `present`
- `late`
- `absent`
- `unknown`

`unknown`은 “그 조/사람의 출석 여부를 아직 모름”이다. 단, `included=true`라면 분모에는 들어간다.

### `attendance_roster_snapshot_events`

관리자 수정 이력.

```sql
attendance_roster_snapshot_events
- id uuid primary key
- snapshot_id uuid not null references attendance_roster_snapshots(id)
- person_id uuid null references people(id)
- event_type text not null
- before jsonb null
- after jsonb null
- reason text null
- created_at timestamptz not null default now()
- created_by uuid null references auth.users(id)
```

Event examples:

- `member_added`
- `member_excluded`
- `member_restored`
- `group_changed`
- `role_changed`
- `attendance_status_changed`
- `snapshot_locked`
- `snapshot_unlocked`

## Snapshot Generation Rule

Snapshot은 다음 시점에 자동 생성한다.

- 관리자가 출석 대시보드에서 특정 주차/부서를 열 때
- 조장이 앱 출석 화면에서 특정 주차/조를 열 때
- 관리자가 리포트를 다운로드할 때

이미 snapshot이 있으면 다시 생성하지 않는다. 기존 snapshot을 기준으로 읽는다.

기본 생성 로직:

```text
1. week.week_date 기준 active memberships를 가져온다.
2. department_id가 같은 membership만 포함한다.
3. person_id distinct 기준으로 1명 1row를 만든다.
4. 같은 person이 여러 active group에 있으면 role/group 우선순위 기준으로 대표 row를 정한다.
5. 같은 주차 출석 기록에 있지만 active membership에는 없는 person은 attendance_snapshot source로 보강한다.
6. 출석 기록이 있는 사람은 기존 attendance status를 snapshot member에 반영한다.
7. 출석 기록이 없는 사람은 `attendance_status='unknown'` 또는 `absent` 정책으로 표시한다.
8. active membership이 0명인데 출석 기록은 있는 과거 후입력 주차는 migration/backfill 후보로 표시한다.
```

대표 row 우선순위:

```text
leader role 우선
group_id 있는 row 우선
starts_at이 가장 이른 row 우선
그 외 display_name 정렬
```

이 규칙은 “한 사람이 같은 부서에서 여러 조에 속할 수 있다”는 구조를 부정하지 않는다. 출석률 분모는 사람 수 기준이므로 snapshot은 person당 1row가 기본이다. 조별 리포트가 필요하면 snapshot member row에 당시 대표 group을 저장하고, 별도 상세 이력은 memberships에서 본다.

## Attendance Calculation

Phase 2 snapshot 적용 후 출석률은 다음 기준으로 계산한다.

```text
분모 = snapshot_members where included = true distinct person count
분자 = included person 중 attendance.status in ('present', 'late')인 distinct person count
결석 = 분모 - 분자
모임없는날 = 분모/분자 계산 제외
```

출석 기록이 없는 사람은 계산에서는 결석으로 본다. UI에서는 “미제출/미확인” 상태를 따로 보여줄 수 있다.

조장이 출석을 제출하지 않은 조도 snapshot에 포함되어 있으면 분모에 들어간다. 이것이 snapshot 구조의 핵심이다.

## Admin UX

출석 대시보드에 다음을 추가한다.

### 대상 명단 상태 카드

```text
출석 대상 102명
시스템 생성
마지막 수정: 없음
```

관리자가 수정한 경우:

```text
출석 대상 104명
관리자 수정됨
마지막 수정: 2026-05-08 이수진
```

### 출석 대상 관리 모달

기능:

- 대상자 검색
- 대상 추가
- 대상 제외
- 제외된 사람 보기
- 조/역할 표시 수정
- 출석 상태 수정
- 수정 사유 입력
- 변경 이력 보기

기본 UX:

```text
현재 대상
[김보영] 동준 상희 조 / member
[유성열] 동준 상희 조 / member

제외된 대상
[박민영] 제외됨 - 해당 주차 타부서 참석

변경 이력
2026-05-08 이수진: 김보영 추가 - 1월 출석 누락 보정
```

### 조별 출석 현황 상세보기 inline edit

현재 출석 현황 대시보드의 “전체 조별 출석 현황” 상세보기는 snapshot 수정의 주 UX가 된다.

관리자는 조별 섹션에서 엑셀처럼 해당 주차 명단을 직접 다룰 수 있어야 한다.

```text
현권 영미 조
[김용훈 ✓] [이지미 ✓] [김주용 ✕] [최애린 ✕] [+]

정헌 진슬 조
[강훈진 ?] [김동주 ?] [구정용 ✓] [+]

RE-BORN(새가족부)
[조명단 불러오기]
```

기능:

- 사람 뱃지 삭제: 해당 주차 snapshot에서 `included=false` 처리한다. 실제 사람/소속/과거 기록은 삭제하지 않는다.
- `+` 버튼: 같은 부서/교회 사람을 검색해서 해당 조의 그 주차 snapshot에 추가한다.
- 조명단 불러오기: 출석 제출이 없던 조라도 현재 또는 선택 기준의 조 구성원을 불러와 그 주차 snapshot member로 생성한다.
- 뱃지 클릭: 출석 상태를 `present/late/absent/unknown` 중 하나로 바꾼다.
- 변경 사유: 과거 주차 수정은 사유 입력을 권장한다.

중요한 원칙:

```text
구성 확정과 출석 제출은 다르다.
출석 여부를 몰라도 그 주차 대상 명단은 확정할 수 있다.
```

예를 들어 1월에 정헌 진슬 조만 출석을 입력했고 다른 조는 제출하지 않았더라도, 관리자는 미제출 조의 당시 구성원을 불러와 분모를 확정할 수 있다. 이 경우 출석 상태는 unknown/absent로 남아도 분모에는 포함된다.

### 조명단 불러오기

조명단 불러오기는 과거 주차 분모 보정의 핵심 UX다.

불러오기 후보:

1. 해당 주차 날짜 기준 active memberships
2. 같은 조의 현재 active memberships
3. 출석 기록에 등장한 legacy directory member

관리자에게는 후보 출처를 표시한다.

```text
김보영 - 현재 조 구성원
이수진 - 출석 기록에 있음
박민영 - 주차 기준 active
```

관리자는 후보를 선택해 snapshot에 추가하거나, 전체 조원 일괄 추가를 할 수 있다.

### 대상 변화 설명

주차를 바꿨을 때 이전 주차 snapshot과 비교한다.

```text
전주 대비 추가 3명: 김보영, 이수진, 박민영
전주 대비 제외 1명: 황준보
```

가능하면 reason/source도 함께 보여준다.

```text
김보영 추가 - attendance_snapshot
이수진 추가 - manual_add
황준보 제외 - manual_exclude
```

## Historical Backfill

과거 주차는 완벽히 복원하지 못한다. 따라서 snapshot backfill에는 `source`와 `reason`을 명확히 남긴다.

Backfill 우선순위:

```text
1. attendance에 등장한 person
2. week_date 기준 active memberships
3. active membership이 0명인 주차는 current active roster를 후보로 제안
4. 자동 확정이 불안정한 주차는 admin review needed로 표시
```

과거 backfill snapshot은 기본적으로 `system_generated`이지만, UI에서 “추정 명단” 안내를 표시한다.

```text
이 주차는 과거 데이터를 기반으로 추정 생성되었습니다.
필요하면 출석 대상 관리에서 수정하세요.
```

## Interaction With Existing Tables

당장 바꾸지 않는 것:

- `attendance.directory_member_id`
- `attendance.group_member_id`
- `prayer_entries.directory_member_id`
- Flutter 출석 저장 shape

이 설계는 read/metric denominator를 안정화하는 작업이다. 출석 저장 FK를 `person_id`로 바꾸는 write-switch는 Phase 3에서 별도 설계한다.

Snapshot member는 `person_id`를 중심으로 하되, legacy 호환을 위해 `legacy_member_directory_id`를 같이 저장한다. 기존 attendance row와 연결할 때 필요하다.

## Error Handling

Snapshot 자동 생성 실패:

- 대시보드는 기존 Phase 2 membership 계산으로 fallback하지 않는다.
- 대신 “출석 대상 명단을 생성하지 못했습니다” 경고를 보여준다.
- 관리자는 재시도할 수 있다.

중복 person 추가:

- 같은 snapshot에 같은 person은 1번만 포함한다.
- 이미 제외된 person을 다시 추가하면 `included=true`로 복원한다.

출석 기록은 있는데 snapshot에 없는 person:

- 화면에 “snapshot 외 출석 기록” 경고를 표시한다.
- 관리자는 해당 person을 snapshot에 추가하거나 기록을 검토한다.

## Testing Plan

DB verification:

- 한 주차/부서에 snapshot header는 1개만 생성된다.
- snapshot member는 person당 1row만 생성된다.
- active memberships 기준 생성 결과가 기대 person 수와 일치한다.
- attendance-only person은 `attendance_snapshot` source로 보강된다.
- 미제출 조에 대해 조명단 불러오기를 실행하면 included snapshot members가 생성된다.
- manual exclude 후 분모에서 제외된다.
- manual add 후 분모에 포함된다.
- attendance status 수정 후 기존 attendance row 또는 snapshot status가 일관되게 반영된다.

Admin smoke:

- 출석 대시보드 진입 시 snapshot 자동 생성
- 리포트 다운로드가 snapshot 분모를 사용
- 대상 관리 모달에서 추가/제외/복원 가능
- 조별 상세보기에서 뱃지 삭제/+추가 가능
- 출석 미제출 조에서 조명단 불러오기 가능
- 뱃지 클릭으로 출석 상태 수정 가능
- 전주 대비 추가/제외 목록 표시
- 조장이 출석 제출하지 않은 조도 분모에 포함

Regression:

- 기존 출석 저장/기도 저장은 깨지지 않는다.
- 모임없는날은 snapshot이 있어도 출석률 계산에서 제외한다.
- Phase 2 consistency SQL mismatch 0 유지

## Rollout Order

1. Dev schema migration: snapshot tables, indexes, RLS
2. RPC: `ensure_attendance_roster_snapshot(department_id, week_id)`
3. RPC: add/remove/restore snapshot member
4. RPC: load group roster into snapshot for unsubmitted groups
5. Admin read: attendance dashboard denominator uses snapshot
6. Admin UI: snapshot status card and management modal
7. Admin UI: group detail inline edit badges
8. Historical backfill script for dev
9. Smoke with 장전제일교회 예닮부 2026년 1월~5월
10. Flutter read compatibility check
11. Prod-safe migration/verification plan

## Non-Goals

- 조장이 분모 명단을 직접 수정하지 않는다.
- 매주 관리자가 확정 버튼을 누르게 하지 않는다.
- Phase 3 전에는 attendance/prayer write FK를 `person_id`로 바꾸지 않는다.
- 과거 주차를 100% 자동 복원한다고 주장하지 않는다.

## Open Follow-Up

대상 명단 수정 권한은 부서 관리자 이상으로 한다. 단, 현재 시스템의 역할 모델에서 “부서 관리자”가 어떤 DB 필드로 판별되는지는 별도 권한 모델 정리와 함께 확정해야 한다.

## Self-Review

- Placeholder scan: no TBD/TODO placeholders remain.
- Consistency: snapshot is the single denominator source after rollout; current roster inference becomes generation input only.
- Scope: this is focused on attendance denominator snapshots, not full attendance/prayer write-switch.
- Ambiguity: historical backfill is explicitly marked as estimated and admin-adjustable.
