# GraceNote Phase 2E Legacy Dependency Map

> Purpose: Phase 2D read-switch 이후에도 남은 legacy 의존을 운영 반영 전에 빠짐없이 추적한다.

## Current Position

Phase 2D에서 관리자 웹의 핵심 read model은 사람 중심으로 상당 부분 전환했다.

| Area | Current State |
| --- | --- |
| 성도상세 | Phase 2 `people/memberships` 기준 소속 표시 |
| 성도명부 | 실제 사람 수와 소속 칩을 Phase 2 기준으로 표시 |
| 조편성 | Kanban 표시/통계/내보내기를 Phase 2 person/membership 기준으로 보강 |
| 대시보드 | 성도 수/미편성 수를 active `memberships.person_id` 기준으로 표시 |
| write-flow | 아직 legacy `member_directory/group_members` + dual-write trigger 유지 |

## Phase 2E Rule

Phase 2E는 legacy 테이블을 바로 삭제하는 단계가 아니다.

```text
1. legacy read 의존 제거
2. legacy write 의존을 안전한 단위로 축소
3. 운영 적용 전 prod-safe verification SQL 작성
4. 앱/Edge Function까지 smoke 통과
5. 그 뒤에 legacy cleanup 여부 판단
```

## Remaining Legacy Dependency Buckets

| Bucket | Files / Area | Current Dependency | Phase 2E Direction | Risk |
| --- | --- | --- | --- | --- |
| Admin dashboard | `admin-web/src/app/page.tsx` | recent members는 아직 `member_directory` 기준 | 최근 가입자도 `member_profiles`/`memberships` 기준으로 전환 검토 | Low |
| Admin member write | `MemberModal`, `SmartBatchModal`, `members/page.tsx`, `members/[id]/page.tsx` | 성도 추가/수정/비활성화는 `member_directory` write | Phase 2E에서는 유지. write-switch는 Phase 3 후보 | High |
| Admin regrouping write | `admin-web/src/app/regrouping/page.tsx`, `regroup_members()` | 조 이동/복사/삭제 저장은 legacy RPC/write | Phase 2E에서는 dual-write 검증 강화. direct memberships write는 보류 | High |
| Attendance admin | `admin-web/src/app/attendance/page.tsx` | 출석 대상/조회가 `member_directory` 중심 | read만 Phase 2 person 기준으로 보강 가능 | High |
| Flutter group/user state | `lib/core/providers/data_providers.dart`, `user_role_provider.dart` | 현재 권한/조 선택이 `group_members/member_directory` 기준 | 앱 smoke 범위 넓힌 뒤 memberships 기반 available roles 검토 | High |
| Flutter attendance/prayer | `grace_note_repository.dart`, prayer/attendance screens | 저장 FK가 legacy id를 사용 | Phase 2E에서는 FK 보존, read 표시만 보강 | High |
| Edge functions | `notify-event`, `notify-scheduler`, `verify-sms` | 알림 대상 조회가 `group_members/member_directory` 기준 | active `memberships` 기준 대상 계산으로 전환 후보 | Medium |
| Search/saved prayers | Flutter search/prayer saved screens | join display가 `member_directory` 기준 | person/member_profile 표시 fallback 추가 | Medium |

## Completed in Phase 2E Start

| Date | Change | Verification |
| --- | --- | --- |
| 2026-05-07 | 관리자 대시보드 성도 수/미편성 수를 active `memberships.person_id` 기준으로 전환. Phase 2 read 실패 시 legacy count fallback 유지 | `npm run lint -- src/app/page.tsx` 0 errors, consistency mismatch 0 |
| 2026-05-09 | Edge Function 알림 대상 조회를 active `memberships` 우선으로 전환. `group_members`는 fallback으로 유지 | `supabase/verify_phase2d_edge_notification_targets_dev_2026-05-09.sql` 추가. 실제 dev deploy/dry-run smoke는 `SUPABASE_ACCESS_TOKEN` 필요 |

## Recommended Next Order

1. Admin dashboard recent members 표시를 유지할지 Phase 2 기준으로 바꿀지 결정한다.
2. 출석 대시보드는 단순 read-switch가 아니라 주차별 출석 대상 snapshot 설계를 먼저 적용한다.
3. Flutter 앱의 `availableMembershipsProvider`와 권한/조 선택 흐름을 Phase 2 `memberships`로 바꿀 수 있는지 별도 smoke 계획을 만든다.
4. Edge Functions 알림 대상 조회 dev deploy/dry-run smoke를 수행한다.
5. Phase 3 write-switch 설계를 시작한다.
6. 그 뒤에만 legacy table cleanup을 논의한다.

## Attendance Snapshot Dependency

출석 대시보드는 `memberships` 현재/과거 이력이나 `attendance` 제출 snapshot을 매번 조합해서 분모를 추론하면 계속 흔들린다.

따라서 Phase 2E 중 attendance read cleanup은 다음 설계를 선행 조건으로 둔다.

```text
docs/superpowers/specs/2026-05-08-gracenote-attendance-roster-snapshot-design.md
```

핵심 결정:

- 주차 + 부서별 출석 대상 snapshot을 자동 생성한다.
- 관리자가 매주 확정하지 않는다.
- 필요한 경우 부서 관리자 이상이 과거/특수 주차 대상만 수정한다.
- 출석률 분모는 snapshot의 included person 수다.
- 조장 출석 제출 여부와 무관하게 snapshot에 포함된 대상은 분모에 들어간다.

## Explicit Non-Goals

- Phase 2E에서 `member_directory`, `group_members`를 삭제하지 않는다.
- Phase 2E에서 출석/기도 저장 FK를 바로 `person_id`로 바꾸지 않는다.
- Phase 2E에서 운영 DB에 직접 SQL을 적용하지 않는다.

## Smoke Checklist

| Screen / Service | Check |
| --- | --- |
| Admin dashboard | 성도 수가 성도명부 actual people/active people과 큰 방향에서 일치 |
| Admin dashboard | 미배정 수가 조편성/성도명부 미배정 표시와 같은 사람 기준으로 보임 |
| Admin members | 기존 Phase 2 진단 issue 0 유지 |
| Admin regrouping | 조 이동/저장 후 Phase 2 진단 issue 0 유지 |
| Flutter app | 출석/기도 저장 기존 smoke 통과 유지 |
| Edge functions | `verify_phase2d_edge_notification_targets_dev_2026-05-09.sql`의 모든 mismatch count 0 |
| Edge functions | dev 함수 배포 또는 dry-run 로그에서 기도 알림/공지/리마인더/등반 알림 대상이 active memberships 기준으로 산출 |
