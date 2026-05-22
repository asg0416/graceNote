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
| Edge functions | `notify-event`, `notify-scheduler`, `verify-sms` | 알림 대상은 memberships 우선 + legacy fallback. SMS verification은 phone/directory compatibility 유지 | 운영 후보. dev deploy/dry-run smoke 통과. 운영 전 prod env vars와 scheduler trigger만 재확인 | Medium |
| Search/saved prayers | Flutter search/prayer screens | 일반 조원 범위 제한, 삭제 조 기록 표시 보정 완료 | 운영 후보. role switch smoke 필수 | Medium |

## Completed in Phase 2E Start

| Date | Change | Verification |
| --- | --- | --- |
| 2026-05-07 | 관리자 대시보드 성도 수/미편성 수를 active `memberships.person_id` 기준으로 전환. Phase 2 read 실패 시 legacy count fallback 유지 | `npm run lint -- src/app/page.tsx` 0 errors, consistency mismatch 0 |
| 2026-05-09 | Edge Function 알림 대상 조회를 active `memberships` 우선으로 전환. `group_members`는 fallback으로 유지 | `supabase/verify_phase2d_edge_notification_targets_dev_2026-05-09.sql` 추가 |
| 2026-05-11 | Admin-web 성도 추가/수정/비활성화와 Flutter 조장 성도 write를 `upsert_member_person_membership` / lifecycle RPC 중심으로 전환 | Phase 2 summary gate 0, targeted lint/analyze 통과 |
| 2026-05-12 | person+department 단위 archive/restore와 church operations 휴지통 추가. restore는 선택한 group만 복구 가능 | selected restore transaction test, Phase 2 summary gate 0 |
| 2026-05-13 | 조편성 저장 RPC와 profile-less group sync 보정. directory-only 성도도 성도명부/조편성/Phase 2 진단이 같은 조를 보도록 수정 | 김보영 케이스 smoke 통과, consistency summary 0 |
| 2026-05-15 | 조 이름 변경 compatibility RPC 분리. generic person upsert가 stale profile을 재검증하지 않도록 조명 변경은 별도 RPC로 처리 | group rename smoke 통과, consistency summary 0 |
| 2026-05-15 | 관리자 출석 snapshot integrity gate 추가 | `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`: all issue counts 0 |
| 2026-05-15 | Edge Function dev deploy/dry-run smoke 완료 | `notify-event`, `notify-scheduler` 모두 `verify_jwt=false`. `notify-scheduler` leader reminder dry-run은 active memberships 우선으로 대상 계산 후 실제 발송 skip. `notify-event` dry-run endpoint reachable |
| 2026-05-16 | 조 active period와 출석 snapshot 제출값 반영 보정 | `20260516000000`, `20260516001000`, `20260516002000` 추가. 삭제/비활성 조는 기록이 있는 과거 주차에만 표시되고, submitted attendance가 자동 snapshot row에 반영됨. snapshot integrity all 0 |
| 2026-05-16 | Edge Function 알림 대상 profile ownership filter 보강 | `member_profiles.profile_id`가 다른 `profiles.person_id`에 명시 연결된 경우 알림 대상에서 제외. stale legacy profile link가 있어도 잘못된 계정으로 알림을 보내지 않음. edge target gate all 0 |
| 2026-05-17 | 운영 복제본 dry-run에서 드러난 pre-Phase2 backfill gap 보정 | `20260517000000_phase3_prod_clone_backfill_repair.sql` 추가. 기존 운영 row의 `people/member_profiles/memberships`와 attendance/prayer person snapshot을 재완성. blocking/auto-repair audit 0, 동일 전화번호 수동 검토 1건 |
| 2026-05-17 | 운영 복제본 manual duplicate phone 1건 정리 | `20260517001000_prod_data_repair_minjaehong_phone.sql` 추가. 장전제일교회 민재홍 전화번호를 확인된 번호로 정정해 민재홍/임진슬 동일 전화번호 gate 0 |
| 2026-05-17 | 기도 알림 폭주 방지 가드 | `20260517002000_guard_prayer_notification_updates.sql` 추가. 이미 published인 기도제목의 person snapshot/backfill update는 알림을 다시 보내지 않고, 신규 published insert 또는 draft→published 전환만 발송 |

## Recommended Next Order

1. 운영용 prod-safe migration order를 최신 Phase 3 파일까지 확정한다.
2. fresh DB 또는 운영 복제본에서 migration 전체 dry-run을 실행한다.
3. 운영 복제본 데이터 감사 패키지를 실행한다:
   - `preprod_data_audit_summary_2026-05-15.sql`
   - `preprod_identity_link_audit_2026-05-22.sql`
   - `preprod_auto_repair_candidates_2026-05-15.sql`
   - `preprod_manual_review_candidates_2026-05-15.sql`
   - `preprod_identity_link_candidates_2026-05-22.sql`
4. 운영 전 필수 gate를 한 번에 실행한다: Phase 2 summary, attendance/prayer snapshot, attendance roster snapshot integrity, edge notification targets.
5. role별 smoke를 실행한다: master/admin/leader/member, admin-web/Flutter, 성도 추가/수정/비활성/복구, 조편성 저장, 출석/기도 저장.
6. legacy FK 제거 계획은 별도 Phase 4로 둔다. 지금 운영 후보는 “person source-of-truth + legacy compatibility” 구조다.

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
| Edge functions | dev 함수 배포/dry-run 로그에서 리마인더 알림 대상이 active memberships 기준으로 산출됨. 운영 전에는 prod env vars와 실제 scheduler trigger만 재확인 |

## Current Remaining Before Prod Prep

| Item | Why It Remains | Required Action |
| --- | --- | --- |
| Prod-safe migration order refresh | manifest의 migration list가 Phase 3 최신 파일까지 확장됨 | 운영 적용 직전 파일 존재/순서 재확인. 2026-05-17 기준 Order 1~48 |
| Fresh migration dry-run | dev DB는 수동 적용 이력이 있어 migration history만 믿으면 위험 | 2026-05-15 local fresh `supabase db reset` 통과. 2026-05-17 운영 복제본에 Order 1~48 적용 후 verification gate all PASS |
| Query-compatible verification SQL | 일부 dev verify 파일은 psql meta command 또는 여러 SELECT 때문에 `supabase db query --file`과 호환되지 않음 | Phase 2 schema는 `verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql`, Phase 3 attendance/prayer는 `verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql`로 대체 |
| Pre-prod security lint | Supabase CLI가 `public.app_config` RLS disabled advisory를 출력했음 | `20260515001000_app_config_rls.sql` 추가. `verify_app_config_rls_dev_2026-05-15.sql` all 0 |
| Edge function smoke | 알림 대상 read-switch는 dev 함수 dry-run까지 확인됨 | 운영 전 prod env vars, scheduled trigger, 실제 FCM 발송 권한만 재확인 |
| Attendance history/snapshot integrity | 삭제 조 과거 출석, unlinked attendance row, submitted attendance snapshot 반영은 운영 데이터에서 새로 드러날 수 있음 | `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`와 `verify_attendance_unlinked_rows_detail_dev_2026-05-16.sql` 실행. unlinked rows/detail이 있으면 운영 반영 전 cleanup 또는 수동 연결 |
| Edge profile ownership integrity | 운영 데이터에도 stale `group_members.profile_id` 또는 `member_profiles.profile_id`가 있을 수 있음 | `verify_phase2d_edge_notification_targets_dev_2026-05-09.sql` all 0. profile이 다른 person으로 명시 연결된 경우 알림 대상에서 제외 |
| Preprod data audit | dev에서 발견한 legacy/person drift 패턴을 운영 복제본에서 사전 탐지해야 함 | `preprod_data_audit_summary_2026-05-15.sql`, `preprod_identity_link_audit_2026-05-22.sql` 실행. `blocking_gate=0`, `auto_repair_candidate`는 승인된 repair SQL 작성, `manual_review`는 자동 수정 금지 |
| Role-based app/admin smoke | 권한별 메뉴가 다르므로 한 계정 smoke만으로 부족 | master/admin/leader/member 체크리스트 수행 |
| Legacy cleanup decision | legacy 테이블 삭제는 아직 위험 | 운영 1차에서는 삭제 금지. 이후 Phase 4에서 FK/backfill/report 영향 재설계 |

## Final Pre-Prod Smoke Matrix

운영 적용 직전에는 아래 smoke를 한 번에 실행한다. 이미 dev에서 대부분 통과했지만, 운영 복제본 dry-run 이후 같은 기준으로 다시 확인한다.

| Role / Surface | Required Smoke |
| --- | --- |
| Master admin | 교회/부서 선택, 성도명부/조편성/출석/휴지통 진입, cross-church 성도 자동 연결이 발생하지 않음 |
| Church admin | 성도 개별 추가, AI 일괄 등록, 기존 성도 같은 교회 다른 부서 연결, 부서/조 이름 변경, 비활성/복구 |
| Department admin | 성도상세 수정, 가족정보/메모 저장, 조편성 저장, 출석 snapshot 수정, 리포트 export |
| Leader | Flutter 조원 명단, 출석 저장/재진입 유지, 기도 저장, 조장 성도 추가/수정, 일반 조원보다 넓은 기도 검색 권한 |
| Member | Flutter 일반 조원 화면, 자기 조 범위 기도 검색 제한, 나의 기도/저장된 기도 표시, 다른 조 개인정보 미노출 |
| Edge functions | dev/prod 각각 `notify-event`, `notify-scheduler` env var 존재, `verify_jwt=false`, scheduler trigger, FCM dry-run 또는 실제 제한 발송 |

## Operation Cutover Principle

운영 1차 반영은 “person source-of-truth + legacy compatibility”다. `member_directory`/`group_members`/출석·기도 legacy FK는 즉시 삭제하지 않는다.

| Decision | Reason |
| --- | --- |
| `people`/`memberships`를 읽기와 write 판단 기준으로 사용 | 다중 소속, 사람 수, 교회 범위 identity 문제를 안정적으로 처리 |
| legacy row는 호환 저장으로 유지 | 기존 앱/리포트/FK/운영 데이터와의 충돌을 줄이고 rollback 경로 확보 |
| 출석/기도 FK 제거는 Phase 4 | historical report, prayer timeline, group snapshot 영향 범위가 커서 운영 1차에서 같이 제거하면 위험 |
