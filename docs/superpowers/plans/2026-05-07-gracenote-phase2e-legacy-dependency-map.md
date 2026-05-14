# GraceNote Phase 2E Legacy Dependency Map

> Purpose: Phase 2D read-switch 이후에도 남은 legacy 의존을 운영 반영 전에 빠짐없이 추적한다.

## Current Position

Phase 2D read-switch와 Phase 3 member write cleanup 이후, 관리자 웹과 Flutter의 핵심 성도/소속 화면은 `people` / `member_profiles` / `memberships`를 우선 사용한다. `member_directory`와 `group_members`는 아직 삭제 대상이 아니라 운영 호환 계층이다.

| Area | Current State |
| --- | --- |
| 성도상세 | Phase 2 `people/memberships` 기준 소속 표시 |
| 성도명부 | 실제 사람 수와 소속 칩을 Phase 2 기준으로 표시 |
| 조편성 | Kanban 표시/통계/내보내기를 Phase 2 person/membership 기준으로 보강 |
| 대시보드 | 성도 수/미편성 수를 active `memberships.person_id` 기준으로 표시 |
| 성도 추가/수정/비활성/복구 | Admin-web과 Flutter 모두 RPC 경유. RPC가 Phase 2를 기준으로 legacy 호환 row를 맞춤 |
| 조편성 저장 | `save_regrouping_memberships` RPC 경유. profile-less directory-only row도 `group_members`/`memberships` 동기화 |
| 출석/기도 저장 | legacy FK를 유지하되 `person_id`, `membership_id`, recorded group/department snapshot을 같이 저장 |
| 관리자 출석 현황 | `attendance_roster_snapshots`가 관리자 확정 분모 source-of-truth |

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
| Admin dashboard | `admin-web/src/app/page.tsx` | recent members display 일부는 legacy row fallback 가능 | 운영 전 smoke로 표시 문제만 확인. source-of-truth 문제는 낮음 | Low |
| Admin member write | `MemberModal`, `SmartBatchModal`, `members/page.tsx`, `members/[id]/page.tsx` | 직접 legacy write 제거. RPC가 Phase 2 기준으로 legacy 호환 저장 | 운영 후보. `member_directory/group_members`는 삭제하지 않음 | Medium |
| Admin regrouping write | `admin-web/src/app/regrouping/page.tsx` | 직접 legacy write 제거. `save_regrouping_memberships` RPC 경유 | 운영 후보. profile-less sync gate 필수 | High |
| Admin archive/lifecycle | `admin-web/src/app/archive/page.tsx` | person+department 단위 비활성/복구 RPC 경유 | 운영 후보. selected restore smoke 필수 | High |
| Attendance admin | `admin-web/src/app/attendance/page.tsx` | 관리자 확정 분모는 snapshot 테이블. leader submission은 `attendance` row 유지 | 운영 후보. snapshot integrity gate 필수 | High |
| Flutter group/user state | `lib/core/providers/data_providers.dart`, `user_role_provider.dart` | active memberships 우선, legacy fallback | 운영 후보. role별 smoke 필수 | Medium |
| Flutter member write | `grace_note_repository.dart` | 조장 성도 추가/수정/비활성은 RPC 경유 | 운영 후보. 앱 smoke 필수 | Medium |
| Flutter attendance/prayer | `grace_note_repository.dart`, prayer/attendance screens | 저장 FK가 legacy id를 유지하지만 Phase 3 snapshot fields도 저장 | 운영 후보. FK 제거는 다음 단계 | High |
| Edge functions | `notify-event`, `notify-scheduler`, `verify-sms` | 알림 대상은 memberships 우선 + legacy fallback. SMS verification은 phone/directory compatibility 유지 | 운영 후보. function deploy/dry-run smoke 필요 | Medium |
| Search/saved prayers | Flutter search/prayer screens | 일반 조원 범위 제한, 삭제 조 기록 표시 보정 완료 | 운영 후보. role switch smoke 필수 | Medium |

## Completed in Phase 2E Start

| Date | Change | Verification |
| --- | --- | --- |
| 2026-05-07 | 관리자 대시보드 성도 수/미편성 수를 active `memberships.person_id` 기준으로 전환. Phase 2 read 실패 시 legacy count fallback 유지 | `npm run lint -- src/app/page.tsx` 0 errors, consistency mismatch 0 |
| 2026-05-09 | Edge Function 알림 대상 조회를 active `memberships` 우선으로 전환. `group_members`는 fallback으로 유지 | `supabase/verify_phase2d_edge_notification_targets_dev_2026-05-09.sql` 추가. 실제 dev deploy/dry-run smoke는 `SUPABASE_ACCESS_TOKEN` 필요 |
| 2026-05-11 | Admin-web 성도 추가/수정/비활성화와 Flutter 조장 성도 write를 `upsert_member_person_membership` / lifecycle RPC 중심으로 전환 | Phase 2 summary gate 0, targeted lint/analyze 통과 |
| 2026-05-12 | person+department 단위 archive/restore와 church operations 휴지통 추가. restore는 선택한 group만 복구 가능 | selected restore transaction test, Phase 2 summary gate 0 |
| 2026-05-13 | 조편성 저장 RPC와 profile-less group sync 보정. directory-only 성도도 성도명부/조편성/Phase 2 진단이 같은 조를 보도록 수정 | 김보영 케이스 smoke 통과, consistency summary 0 |
| 2026-05-15 | 조 이름 변경 compatibility RPC 분리. generic person upsert가 stale profile을 재검증하지 않도록 조명 변경은 별도 RPC로 처리 | group rename smoke 통과, consistency summary 0 |
| 2026-05-15 | 관리자 출석 snapshot integrity gate 추가 | `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`: all issue counts 0 |

## Recommended Next Order

1. 운영용 prod-safe migration order를 최신 Phase 3 파일까지 확정한다.
2. fresh DB 또는 운영 복제본에서 migration 전체 dry-run을 실행한다.
3. 운영 전 필수 gate를 한 번에 실행한다: Phase 2 summary, attendance/prayer snapshot, attendance roster snapshot integrity, edge notification targets.
4. role별 smoke를 실행한다: master/admin/leader/member, admin-web/Flutter, 성도 추가/수정/비활성/복구, 조편성 저장, 출석/기도 저장.
5. legacy FK 제거 계획은 별도 Phase 4로 둔다. 지금 운영 후보는 “person source-of-truth + legacy compatibility” 구조다.

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

- 운영 1차 반영에서 `member_directory`, `group_members`를 삭제하지 않는다.
- 운영 1차 반영에서 출석/기도 legacy FK를 제거하지 않는다.
- Phase 2E에서 운영 DB에 직접 SQL을 적용하지 않는다.
- 운영 반영은 migration files + prod-safe verification SQL 기준으로만 한다.

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

## Current Remaining Before Prod Prep

| Item | Why It Remains | Required Action |
| --- | --- | --- |
| Prod-safe migration order refresh | manifest의 migration list가 Phase 3 최신 파일까지 확장됨 | 운영 적용 직전 파일 존재/순서 재확인 |
| Fresh migration dry-run | dev DB는 수동 적용 이력이 있어 migration history만 믿으면 위험 | 2026-05-15 local fresh `supabase db reset` 통과. 운영 적용 직전 운영 복제 DB에서 재실행 |
| Query-compatible verification SQL | 일부 dev verify 파일은 psql meta command 또는 여러 SELECT 때문에 `supabase db query --file`과 호환되지 않음 | Phase 2 schema는 `verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql`, Phase 3 attendance/prayer는 `verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql`로 대체 |
| Pre-prod security lint | Supabase CLI가 `public.app_config` RLS disabled advisory를 출력 | person migration 실패는 아니지만 운영 전 RLS/policy 의사결정 필요 |
| Edge function smoke | 알림 대상 read-switch는 코드/SQL gate만 있고 실제 함수 dry-run은 별도 | dev deploy 또는 dry-run log 확인 |
| Role-based app/admin smoke | 권한별 메뉴가 다르므로 한 계정 smoke만으로 부족 | master/admin/leader/member 체크리스트 수행 |
| Legacy cleanup decision | legacy 테이블 삭제는 아직 위험 | 운영 1차에서는 삭제 금지. 이후 Phase 4에서 FK/backfill/report 영향 재설계 |
