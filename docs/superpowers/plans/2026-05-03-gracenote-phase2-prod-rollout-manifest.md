# GraceNote Phase 2 Prod Rollout Manifest

> Purpose: 개발 서버 개편 중 발견한 모든 예외와 수정사항을 운영 반영 전에 빠짐없이 대조하기 위한 최종 실행표다. 새 문제가 발견되면 이 문서의 Issue Registry와 Prod Execution Gates에 즉시 추가한다.

## Operating Rule

- 운영 DB에는 사용자 명시 승인 없이 쓰기 작업을 하지 않는다.
- 운영 반영은 기억이나 대화 맥락이 아니라 이 문서와 검증 SQL 결과를 기준으로 한다.
- 새 마이그레이션은 대응 검증 SQL 또는 명시된 수동 QA gate가 없으면 운영 후보가 아니다.
- dev-only 데이터 보정 SQL은 운영에 자동 적용하지 않는다.
- UI에서 발견한 문제도 운영 반영 누락 방지를 위해 이 문서에 남긴다.
- dev DB migration history와 실제 schema가 다를 수 있으므로 `supabase db push`를 무작정 사용하지 않는다. 운영 적용 기준은 fresh prod schema + migration file + prod-safe verification SQL이다.

## Dev DB Drift Control

상세 문서: `docs/superpowers/plans/2026-05-03-gracenote-dev-db-drift-log.md`

| 항목 | 현재 상태 | 운영 영향 |
| --- | --- | --- |
| Dev migration history | `20260501003000`까지만 기록 | 이후 migration은 dev에서 수동 적용/검증 흔적으로 취급 |
| Local migration files | `20260502000000` ~ `20260504002000` 존재 | 운영 반영 후보는 파일 기준으로 관리 |
| P0 dev apply | `20260503005000_p0_hard_delete_guardrails.sql`의 object가 dev에 직접 적용됨 | 운영에는 직접 실행 기록이 아니라 migration 파일 전체를 적용 |
| Dev `db push` | 금지 | 중복 적용/충돌 가능 |

## Current Production State

| Area | Prod State | Note |
| --- | --- | --- |
| Phase 1 FK guardrails | Applied | `prayer_entries.group_id`, `attendance.group_member_id` cascade 위험 차단 완료 |
| Phase 1.5 FK guardrails | Applied | `attendance.directory_member_id`, `prayer_entries.directory_member_id` cascade 위험 차단 완료 |
| Phase 2 schema | Not applied | `people`, `person_identifiers`, `member_profiles`, `memberships` 운영 미적용 |
| Phase 2 backfill | Not applied | 운영 데이터 기준 dry-run 필요 |
| Phase 2 dual-write triggers | Not applied | dev에서만 검증 중 |
| Admin Phase 2 diagnostics | Code exists locally | 운영 배포 전 Phase 2 테이블/RLS 존재 여부 확인 필요 |

## Current Work Position

현재 실제 위치는 Phase 2D read-switch, Phase 2E/Phase 3 write compatibility, admin UI polish를 dev에서 통합 검증한 뒤 운영 복제본 dry-run/data audit 준비 단계다.

| Phase | Actual State | Meaning |
| --- | --- | --- |
| Phase 1 | Prod applied | 출석/기도 cascade 유실 위험 차단 완료 |
| Phase 1.5 | Prod applied | directory_member 잔여 FK 위험 차단 완료 |
| Phase 2A | Dev complete, prod not applied | 신규 사람/소속 테이블 schema dev 검증 완료 |
| Phase 2B | Dev complete, prod not applied | 운영 복제 데이터 기준 backfill dev 검증 완료 |
| Phase 2C | Dev gate complete | dual-write/write-flow DB 검증, Admin/Flutter/SmartBatch smoke 완료 |
| P0 hard delete gate | Dev verified, prod not applied | 부서/조/주차/명부 hard-delete 차단 운영 후보 |
| Phase 2D | Dev code broadly complete | 성도상세/성도명부/조편성/관리자 대시보드/관리자 출석/Flutter 표시 read/Edge 알림 대상 read가 Phase 2 우선 + legacy fallback 구조로 전환됨 |
| Phase 2E | Dev code broadly complete, prod not applied | 성도 추가/수정/비활성/복구, 조편성 저장, 부서/조명 변경, Flutter 조장 성도 추가가 RPC 중심으로 전환됨. legacy 테이블은 호환 계층으로 유지 |
| Phase 3 write compatibility | Dev code broadly complete, prod not applied | 출석/기도는 person snapshot 필드를 저장/조회하지만 `attendance`/`prayer_entries`의 legacy FK 제거는 운영 안정화 이후 별도 단계로 연기 |

**운영 반영 타이밍**: 운영 1차는 “person source-of-truth + legacy compatibility”로 간다. 운영 적용 전에는 fresh/staging DB dry-run, preprod data audit, role별 smoke를 통과해야 한다. `member_directory` / `group_members` / 출석/기도 legacy FK 삭제는 이번 운영 1차 범위가 아니라 Phase 4 cleanup이다.

SmartBatch는 Phase 2C에 포함한다. 대량 등록은 여러 `member_directory` row와 Phase 2 `memberships`를 한 번에 만드는 write-flow이므로, Phase 2C 종료 전 DB rollback verify와 UI smoke를 모두 통과해야 한다.

UI/app smoke checklist: `docs/superpowers/plans/2026-05-04-gracenote-phase2c-ui-app-smoke-checklist.md`

Prod dry-run runbook: `docs/superpowers/plans/2026-05-15-gracenote-prod-dry-run-runbook.md`

Preprod data audit package:
- `supabase/preprod_data_audit_summary_2026-05-15.sql`
- `supabase/preprod_auto_repair_candidates_2026-05-15.sql`
- `supabase/preprod_manual_review_candidates_2026-05-15.sql`

운영 복제본/staging에는 migration dry-run 직후 위 3개 SQL을 실행한다. 목적은 dev에서 이미 발견한 김보영/유성열류 legacy drift를 운영에서 다시 재현하는 것이 아니라, 같은 패턴을 적용 전 숫자와 후보 목록으로 잡아 자동 보정/수동 검토로 분류하는 것이다.

| Audit Output | Meaning | Prod Rule |
| --- | --- | --- |
| `blocking_gate` issue | people/membership/snapshot FK 또는 snapshot source-of-truth integrity 문제 | 운영 반영 전 0이어야 함 |
| `auto_repair_candidate` issue | inactive/ended 상태 불일치, legacy 호환 row drift처럼 규칙 기반 보정 가능성이 높은 문제 | 운영 복제본에서 보정 SQL 작성/검증 후 승인된 항목만 prod 적용 |
| `manual_review` issue | 같은 교회 전화번호 중복, 같은 이름 다중 person, cross-church same phone 등 자동 병합 위험 후보 | 자동 수정 금지. 운영자 확인 리포트로 관리 |

2026-05-06 resync: 다른 AI 작업 이후 현재 상태를 재검증했다. 이후 Flutter 앱 smoke와 SmartBatch 브라우저 smoke까지 통과했고, 최종 DB rollback/consistency gate도 통과했다. Phase 2C는 dev 기준 완료로 본다.

| SmartBatch Gate | Required Result |
| --- | --- |
| DB rollback verify | `verify_phase2_smart_batch_write_flow_dev_2026-05-03.sql` 통과 |
| UI smoke | 대량 등록 후 legacy/Phase 2 count 일치 |
| Candidate search | 현재 교회 active 성도만 후보 표시 |
| Duplicate handling | 같은 사람/전화번호 후보가 중복 row 수만큼 반복 표시되지 않음 |
| Before Phase 2D | SmartBatch가 Phase 2 불일치 row를 만들지 않음 |

2026-05-06 Phase 2C closeout:
- SmartBatch browser smoke: 통과
- Flutter manual smoke: 출석 저장/재진입 유지 통과, 기도 저장/목록 표시 통과, 모임없는날 정상
- 주차 soft-disable: UI가 없으므로 코드/DB gate로만 관리
- 조원 active filter: 별도 UI 기능이 아니라 비활성 row가 앱 명단에 섞이지 않는지 보는 코드/DB gate
- Final DB gates: consistency 0, dual-write ready, SmartBatch/regrouping/member_directory rollback verify 통과

2026-05-07 Phase 2D start:
- 1차 read-switch 대상: `admin-web/src/app/members/[id]/page.tsx`
- 성도상세의 “소속 정보” 카드를 Phase 2 `memberships` 기준으로 표시하도록 구현
- Phase 2 연결이 없을 때만 legacy `_affiliations` fallback 표시
- 기도제목 조회 범위는 Phase 2 `person_id`의 `member_profiles`와 같은 교회 scoped profile/directory id 기준으로 제한
- write path는 변경하지 않음: 프로필 수정, 가족 정보 수정, 메모 저장, 비활성화는 legacy write + dual-write trigger 유지
- Verification: `npm run lint -- src/app/members/[id]/page.tsx` 통과, Phase 2 consistency gate mismatch 0
- Manual smoke: 여러 조에 속한 사람을 서로 다른 legacy 상세 링크로 들어가도 같은 `people` 정보와 전체 active memberships가 보임. inactive/ended 이력도 현재 소속과 분리되어 보임

2026-05-07 Phase 2D second target:
- 2차 read-switch 대상: `admin-web/src/app/members/page.tsx`
- 성도명부 목록은 아직 write-flow 때문에 `member_directory.id`로 진입/수정하지만, 표시 기준은 Phase 2 `member_profiles.person_id`를 우선 사용한다.
- 상단 숫자는 legacy row 수가 아니라 “실제 사람 수”를 기본으로 보여준다. 한 사람이 여러 조/소속 row를 가지고 있어도 사람 수는 1명으로 계산한다.
- Phase 2 목록 진단은 실제 사람 수와 active 소속 수를 함께 표시한다. row/membership count는 보조 정보로만 남긴다.
- 조편성 kanban과 성도명부 write path는 아직 legacy 기준 유지. 순수 person route(`/people/[id]`)는 Phase 2E 이후 별도 작업이다.

2026-05-16 Phase 3 attendance snapshot hardening:
- 삭제/비활성 조라도 과거 출석/기도 기록이 있던 주차에는 화면에 나타나야 한다. 이를 위해 `groups.active_from` / `active_until` 기준을 도입하고, 과거 attendance/prayer 기록으로 `active_from`을 backfill한다.
- 출석 row가 `person_id`, `directory_member_id`, `membership_id` 모두 없는 경우는 사람 기준 source-of-truth로 쓸 수 없으므로 제출/인사이트 집계에서 제외하고 integrity gate에서 0이어야 한다.
- 제출된 출석 row가 snapshot의 자동 명단 row와 같은 person/group/week를 가리키면 제출값이 snapshot row에 반영되어야 한다. 단, 관리자가 직접 수정한 snapshot row는 자동 덮어쓰기하지 않는다.
- Dev smoke: 삭제테스트조처럼 종료된 조의 2026-05-03 출석이 관리자 출석 현황과 성도상세 기도 타임라인에 함께 보임.

## Prod Migration Candidate Order

이 순서는 운영 반영 후보 순서다. 운영 적용 전 각 단계의 gate를 통과해야 한다.

| Order | File | Purpose | Prod Gate |
| --- | --- | --- | --- |
| 1 | `supabase/migrations/20260430010000_phase2_people_memberships_schema.sql` | 사람 중심 신규 테이블 4개 추가 | schema verify에서 테이블/FK/RLS/index 존재 확인 |
| 2 | `supabase/migrations/20260430011000_phase2_member_profiles_profile_nonunique.sql` | `member_profiles.profile_id` unique 제거 | 동일 profile이 여러 directory row를 가질 수 있음 확인 |
| 3 | `supabase/migrations/20260430012000_phase2_person_identifiers_source_kind_unique.sql` | identifier unique 기준을 source+kind로 보정 | `auth_user`, `legacy_profile`, `legacy_directory`, `phone` 공존 확인 |
| 4 | `supabase/backfill_phase2_people_memberships_dev_2026-04-30.sql` 기반 prod-safe backfill | 운영 기존 데이터를 새 테이블로 채움 | 운영용 파일명/로그/rollback 계획 별도 생성 후 적용 |
| 5 | `supabase/migrations/20260430020000_phase2c_dual_write_sync.sql` | legacy write를 Phase 2 테이블에 동기화 | dual-write verify 통과 |
| 6 | `supabase/migrations/20260430021000_phase2c_group_member_sync_record_fix.sql` | `group_members` 기반 sync 보정 | stale/missing mismatch 0 |
| 7 | `supabase/migrations/20260430022000_phase2_read_policies.sql` | Phase 2 RLS read policy 추가 | master/admin 계정으로 read 검증 |
| 8 | `supabase/migrations/20260501000000_phase2_directory_membership_corrections.sql` | directory-only/stale membership 보정 | consistency verify 전 항목 0 |
| 9 | `supabase/migrations/20260501001000_phase2_member_directory_trigger_columns.sql` | member_directory trigger 컬럼 범위 보정 | trigger columns verify 통과 |
| 10 | `supabase/migrations/20260501002000_phase2_sync_trigger_depth_correction.sql` | nested legacy trigger 경로 보정 | nested write 후 Phase 2 sync 유지 |
| 11 | `supabase/migrations/20260501003000_phase2_member_directory_trigger_all_updates.sql` | member_directory update 누락 방지 | regrouping/list/detail 비교 all green |
| 12 | `supabase/migrations/20260502000000_phase2_member_directory_delete_sync.sql` | deleted directory row의 active membership orphan 방지 | `active_orphan_count = 0` |
| 13 | `supabase/migrations/20260503000000_phase2_identifier_phone_update_sync.sql` | phone identifier가 성도/프로필 전화번호 수정에 따라 갱신되도록 보정 | member_directory write-flow verify에서 새 번호 1, 옛 번호 0 |
| 14 | `supabase/migrations/20260503001000_phase2_profile_identifier_relink_sync.sql` | 온보딩 시 `profiles.person_id` 변경에 따라 auth/profile identifiers와 profile-only member_profile을 재연결 | profile/onboarding write-flow verify 통과 |
| 15 | `supabase/migrations/20260503002000_phase2_group_delete_sync.sql` | 조 삭제 시 active membership과 active directory group_name이 삭제된 조를 계속 가리키지 않도록 보정 | group lifecycle verify에서 active null group 0, deleted group_name 0 |
| 16 | `supabase/migrations/20260503003000_phase2_department_delete_sync.sql` | 부서 삭제 전 active memberships를 ended 처리하고 profiles.department_id를 정리 | department lifecycle verify 통과 |
| 17 | `supabase/migrations/20260503004000_phase2_group_delete_department_cascade_fix.sql` | 부서 삭제 cascade 중 group delete trigger가 삭제 중인 member_directory를 업데이트하지 않도록 보정 | department + group lifecycle verify 동시 통과 |
| 18 | `supabase/migrations/20260503005000_p0_hard_delete_guardrails.sql` | 운영 사고 위험이 큰 부서/조/주차 hard delete를 soft-end/비활성화 정책으로 전환 | P0 object verify, hard-delete search, UI smoke |
| 19 | `supabase/migrations/20260504000000_p0_member_directory_inactive_sync_fix.sql` | 성도 비활성화 시 linked `group_members`와 `memberships`까지 inactive/ended 처리 | inactive `member_directory` with active `memberships` = 0 |
| 20 | `supabase/migrations/20260504001000_p0_member_directory_assignment_scope_fix.sql` | inactive 명부 row가 active assignment unique를 막지 않게 하고, 전화번호 중복 차단을 같은 교회 active 성도 기준으로 제한 | inactive assignment release + cross-church same phone verify 통과 |
| 21 | `supabase/migrations/20260504002000_phase2_church_scoped_identity_guardrails.sql` | `person_id` 자동 병합과 `profile_id` 연결을 같은 교회 범위로 제한 | cross-church same name/phone person 분리, cross-church profile link 차단 |
| 22 | `supabase/migrations/20260508000000_attendance_roster_snapshots.sql` | 주차+부서별 관리자 확정 출석 대상 snapshot 테이블 추가 | snapshot schema/object verify |
| 23 | `supabase/migrations/20260508001000_attendance_snapshot_attendance_seed.sql` | 기존 출석 기록 기반 snapshot seed | snapshot seed 후 duplicate/missing person gate |
| 24 | `supabase/migrations/20260508002000_attendance_snapshot_member_management.sql` | snapshot 구성원 포함/제외/출결 수정 RPC 추가 | snapshot member management smoke |
| 25 | `supabase/migrations/20260508003000_attendance_snapshot_bulk_roster_load.sql` | 미제출 조 명단 일괄 불러오기 RPC 추가 | bulk roster load smoke |
| 26 | `supabase/migrations/20260509000000_phase3_attendance_prayer_person_snapshot.sql` | 출석/기도 row에 person/membership/group/department snapshot 필드 보강 | `verify_phase3_attendance_prayer_person_snapshot_dev_2026-05-09.sql` all 0 |
| 27 | `supabase/migrations/20260511000000_phase3_member_write_rpc.sql` | 성도 추가/수정 write RPC 추가 | member write smoke + consistency summary all 0 |
| 28 | `supabase/migrations/20260511001000_phase3_member_write_rpc_upsert_fix.sql` | member write RPC upsert edge 보정 | SmartBatch/개별등록 smoke |
| 29 | `supabase/migrations/20260511002000_phase3_member_lifecycle_rpc.sql` | 성도 활성/비활성 lifecycle RPC 추가 | inactive/restore smoke |
| 30 | `supabase/migrations/20260512000000_phase3_person_department_lifecycle_rpc.sql` | person+department 단위 archive/restore 모델 도입 | 다중 소속 비활성/복구 smoke |
| 31 | `supabase/migrations/20260512001000_phase3_person_department_lifecycle_rpc_group_optional_fix.sql` | group optional restore 보정 | department-only restore smoke |
| 32 | `supabase/migrations/20260512002000_phase3_person_department_lifecycle_legacy_canonical_fix.sql` | restore 시 canonical legacy row 선택 보정 | duplicate assignment conflict 0 |
| 33 | `supabase/migrations/20260512003000_phase3_person_department_lifecycle_restore_directory_resolution.sql` | 복구 시 directory resolution 보강 | inactive person restore smoke |
| 34 | `supabase/migrations/20260512004000_phase3_person_department_restore_no_rearchive.sql` | restore 중 trigger가 다시 archive하지 않도록 보정 | restore 후 active memberships 유지 |
| 35 | `supabase/migrations/20260512005000_phase3_person_department_restore_dedupe_groups.sql` | 같은 group 중복 restore 방지 | duplicate active membership 0 |
| 36 | `supabase/migrations/20260512006000_phase3_person_department_restore_dedupe_group_members.sql` | legacy `group_members` 중복 restore 방지 | duplicate active group_members 0 |
| 37 | `supabase/migrations/20260512007000_phase3_person_department_restore_prefer_active_legacy.sql` | 이미 active인 legacy row 우선 사용 | active legacy duplicate conflict 0 |
| 38 | `supabase/migrations/20260512008000_phase3_person_department_restore_prefer_active_legacy_alias_fix.sql` | active legacy preference alias fix | restore smoke 유지 |
| 39 | `supabase/migrations/20260512009000_phase3_person_department_archive_events_selected_restore.sql` | archive event와 selected group restore 도입 | 선택한 조만 복구되는지 smoke |
| 40 | `supabase/migrations/20260512010000_phase3_regrouping_save_rpc.sql` | 조편성 저장을 RPC 중심으로 전환 | regrouping save smoke + consistency summary all 0 |
| 41 | `supabase/migrations/20260513000000_phase3_regrouping_profileless_group_sync.sql` | `profile_id=null` directory-only 성도의 group sync 보정 | 김보영/profile-less sync gate all 0 |
| 42 | `supabase/migrations/20260515000000_phase3_group_rename_assignment_rpc.sql` | 조명 변경 compatibility sync를 전용 RPC로 분리 | group rename smoke + consistency summary all 0 |
| 43 | `supabase/migrations/20260515001000_app_config_rls.sql` | `app_config` RLS 활성화, service_role full access + `edge_function_base_url` read-only policy 추가 | `verify_app_config_rls_dev_2026-05-15.sql` all 0 |
| 44 | `supabase/migrations/20260516000000_phase3_group_active_period.sql` | 조의 active 기간(`active_from`, `active_until`)을 도입하고 출석/기도/조 목록에서 기간 기준 표시 가능하게 함 | 삭제/비활성 조가 기록이 있는 과거 주차에는 보이고 생성 전 주차에는 보이지 않음 |
| 45 | `supabase/migrations/20260516001000_phase3_group_active_period_history_backfill.sql` | 과거 attendance/prayer 기록으로 `groups.active_from`을 보정 | `attendance_rows_group_outside_active_period = 0` |
| 46 | `supabase/migrations/20260516002000_attendance_snapshot_apply_submitted_person_rows.sql` | 제출 출석 row가 자동 snapshot row에 반영되도록 `ensure_attendance_roster_snapshot()` 보정 | 삭제/비활성 조의 제출 출석이 snapshot/리포트에 반영, manual snapshot row는 자동 덮어쓰기 안 함 |
| 47 | `supabase/migrations/20260517000000_phase3_prod_clone_backfill_repair.sql` | 운영 복제본 dry-run에서 드러난 기존 운영 데이터 backfill gap 보정. pre-Phase2 row의 people/member_profiles/memberships와 attendance/prayer snapshot을 재완성 | stale missing directory membership 0, attendance/prayer missing person 0. 동일 교회 동일 전화번호 후보는 자동 병합하지 않고 manual review로 남김 |
| 48 | `supabase/migrations/20260517001000_prod_data_repair_minjaehong_phone.sql` | 운영 복제본 audit에서 확인된 민재홍/임진슬 동일 전화번호를 민재홍 실제 번호로 정정 | `identity_candidate_same_church_phone = 0`, duplicate phone manual review 0 |
| 49 | `supabase/migrations/20260517002000_guard_prayer_notification_updates.sql` | published 기도제목 row의 metadata/backfill update가 push 알림을 다시 발송하지 않도록 `notify_on_event()` 가드 추가 | 신규 published insert 또는 draft→published 전환만 기도 알림 발송. Phase 3 person snapshot 보정/운영 backfill 중 알림 폭주 방지 |

주의: 22~49는 현재 dev 기준 운영 후보지만, 운영 DB에 바로 `db push`하지 않는다. 운영 적용 전 fresh DB 또는 운영 복제본에서 위 순서대로 dry-run하고, 아래 “Prod Execution Gates”를 통과해야 한다.

## Hard Delete Gate

Phase 2 운영 반영 전에는 hard delete 전수조사에서 `P0`로 분류된 경로를 먼저 막는다.

상세 감사 문서: `docs/superpowers/plans/2026-05-03-gracenote-hard-delete-audit.md`

| Priority | Target | Required Before Prod |
| --- | --- | --- |
| P0 | `churches` delete | 운영 UI에서 hard delete 제거 또는 archive 정책 도입 |
| P0 | `departments` delete | 부서 삭제를 부서 종료/비활성화로 전환 |
| P0 | `groups` delete | 조 삭제를 조 종료/비활성화로 전환 |
| P0 | `regrouping` group/member_directory delete | 조편성 저장 중 실수로 현재 데이터가 영구 삭제되지 않도록 전환 |
| P0 | `weeks.delete()` | 주차 삭제 금지. `weeks.is_active=false` 또는 예배 없음 flow로 전환 |
| P1 | `notices`, `inquiries` delete | 상용화 전 soft delete 정책 확정 |
| P2 | push token, SMS verification, prayer interaction toggle | hard delete 유지 가능 |

## Local Change Classification

현재 로컬 변경 파일은 운영 반영 전에 다음처럼 분류한다.

| Category | Files | Prod Rule |
| --- | --- | --- |
| DB prod candidates | `supabase/migrations/20260430010000_*` ~ `20260517002000_*` | 운영 적용 후보. 순서와 gate를 통과해야 함 |
| DB already prod-applied candidates | `20260429000000_phase1_fk_guardrails.sql`, `20260430000000_phase1_5_directory_member_guardrails.sql` | 운영 적용 완료 상태와 실제 schema 재확인 후 중복 적용 금지 |
| Admin UI prod candidates | `admin-web/src/app/churches/page.tsx`, `admin-web/src/app/departments/page.tsx`, `admin-web/src/app/regrouping/page.tsx`, `admin-web/src/app/members/page.tsx`, `admin-web/src/app/members/[id]/page.tsx`, `admin-web/src/app/archive/page.tsx`, `admin-web/src/app/attendance/page.tsx`, `admin-web/src/app/page.tsx`, `admin-web/src/components/MemberModal.tsx`, `admin-web/src/components/SmartBatchModal.tsx`, `admin-web/src/components/Sidebar.tsx`, `admin-web/src/components/MemberBadge.tsx`, `admin-web/src/components/kanban/KanbanColumn.tsx`, `admin-web/src/components/RichTextEditor.tsx` | person 구조 read/write, 비활성 관리, 조편성, 출석 snapshot, UI polish 운영 후보. 운영 배포 전 role별 UI smoke 필요 |
| Admin active-filter candidates | `admin-web/src/app/in-app-messages/IamForm.tsx`, `admin-web/src/app/notices/NoticeForm.tsx` | inactive 부서/조 노출 방지. 기존 화면 회귀 확인 필요 |
| Flutter prod candidates | `lib/core/repositories/grace_note_repository.dart`, `lib/core/providers/data_providers.dart`, `lib/core/providers/user_role_provider.dart`, Flutter 출석/기도/검색/저장된 기도/관리자 상세 관련 화면 | person 구조 read, 조장 성도 추가 RPC, 출석/기도 snapshot 저장. master/admin/leader/member role별 앱 smoke 필요 |
| Edge function candidates | `supabase/functions/notify-event`, `supabase/functions/notify-scheduler`, `supabase/functions/verify-sms` | memberships 우선 알림 대상과 dev/prod SMS auth 환경 확인. 운영 전 env vars, `verify_jwt=false`, scheduler trigger 재확인 |
| Preprod verification/audit gates | `scripts/preprod-*.mjs`, `supabase/preprod_*_2026-05-15.sql`, query-compatible `verify_*summary*_2026-05-15.sql` | 운영 복제본/fresh DB에서만 실행. prod 직접 mutation 금지 |
| Attendance snapshot integrity/detail gates | `supabase/verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`, `supabase/verify_attendance_unlinked_rows_detail_dev_2026-05-16.sql` | snapshot source-of-truth integrity, unlinked attendance row, group active period drift 확인. 운영 전 blocking 0이어야 함 |
| Snapshot/dev reference | `supabase/migration_list.*.txt` | 운영 적용 금지. drift 비교용 |
| Local docs | `docs/superpowers/plans/*` | 운영 적용 판단 기준. 코드 배포 대상은 아님 |

주의: admin-web 전체 lint는 기존 unrelated lint debt 때문에 현재 gate로 쓰기 어렵다. 운영 후보 판정은 targeted lint/typecheck, 화면 smoke, DB verification을 함께 사용한다.

## Dev-Only Files

이 파일들은 개발 서버 정리 또는 검증용이다. 운영에는 자동 적용하지 않는다.

| File | Status | Prod Rule |
| --- | --- | --- |
| `supabase/fix_phase2test_cross_church_dev_2026-05-02.sql` | DEV ONLY | 사용자가 만든 dev test pollution 정리. 운영 적용 금지 |
| `supabase/fix_minjaehong_phone_dev_2026-05-01.sql` | DEV correction | 운영에도 같은 오염이 있으면 사용자 승인 후 별도 prod correction으로 재작성 |
| `supabase/fix_phase2c_smartbatch_duplicate_person_dev_2026-05-06.sql` | DEV ONLY | SmartBatch smoke 중 생성된 dev 테스트 성도 중복 person 오염 정리. 운영 적용 금지 |
| `supabase/prod_public_data_for_dev_2026-04-29.sql` | DEV seed | 운영 데이터를 dev에 복제한 dump. 운영 적용 금지 |
| `supabase/dev_align_to_prod_baseline_2026-04-29.sql` | DEV alignment | dev를 prod 기준선에 맞춘 파일. 운영 적용 금지 |
| `supabase/schema_dump.*.sql` | Snapshot | 비교/감사용. 운영 적용 금지 |
| `supabase/migration_list.*.txt` | Snapshot | 비교/감사용. 운영 적용 금지 |
| `supabase/cleanup_future_data.sql`, `supabase/prevent_future_inserts.sql`, `supabase/seed_test_accounts.sql` | Local/dev utility | 운영 적용 금지. 필요 시 별도 prod-safe migration으로 재작성 |
| `supabase/fix_data_integrity.sql`, `supabase/fix_leader_access_secure.sql`, `supabase/fix_missing_emails.sql`, `supabase/fix_person_id_mismatch.sql`, `supabase/fix_schema_schema_cache.sql` | Historical local fix files | 현재 운영 실행표 기준 적용 대상 아님. 운영에서 같은 문제가 발견되면 preprod audit 결과를 근거로 새 correction migration 작성 |
| `supabase/migration_11_inactivation.sql` ~ `supabase/migration_19_auth_cleanup.sql`, `supabase/migration_registration_overhaul.sql`, `supabase/sync_trigger.sql` | Historical root migration files | `supabase/migrations/`의 timestamp migration이 운영 기준이다. root SQL 직접 적용 금지 |

## Direct Dev SQL Log

직접 SQL은 운영 적용 근거가 아니다. 운영 적용은 migration 파일과 prod-safe 검증 SQL 기준으로만 수행한다.

| Date | Dev SQL | Result | Follow-up |
| --- | --- | --- | --- |
| 2026-05-03 | `alter table public.departments add column if not exists is_active boolean default true, add column if not exists ended_at timestamp with time zone` | dev에 `departments.is_active`, `departments.ended_at` 생성 | P0 migration의 첫 부분 직접 적용 |
| 2026-05-03 | `20260503005000_p0_hard_delete_guardrails.sql`의 나머지 statements를 개별 실행 | dev에 P0 함수/트리거/인덱스/view까지 적용 | 운영은 직접 실행 로그가 아니라 migration 파일 전체 기준 |
| 2026-05-04 | `handle_group_soft_end()`, `handle_department_soft_end()` 재적용 | P0 함수의 `memberships.ended_at` 오타를 실제 컬럼 `memberships.ends_at`로 수정 | `20260503005000_p0_hard_delete_guardrails.sql` 파일도 동일하게 수정 |
| 2026-05-04 | `phase2_sync_member_directory()` 재적용 | `member_directory.is_active=false` 시 linked `group_members`와 `memberships`도 inactive/ended 처리 | `20260504000000_p0_member_directory_inactive_sync_fix.sql`에 반영 |
| 2026-05-04 | `20260504001000_p0_member_directory_assignment_scope_fix.sql` 적용 | inactive row 5건의 `group_name`을 비우고, phone uniqueness를 같은 교회 active 성도 기준으로 제한 | 운영은 migration 파일 기준으로 적용 |
| 2026-05-04 | `20260504002000_phase2_church_scoped_identity_guardrails.sql` 적용 | cross-church profile link 1건 정리, legacy person/profile sync를 같은 교회 범위로 제한 | 운영은 migration 파일 기준으로 적용 |
| 2026-05-06 | `fix_phase2c_smartbatch_duplicate_person_dev_2026-05-06.sql` 적용 | SmartBatch smoke 중 생성된 inactive/unassigned dev 테스트 row의 별도 `people`를 active person으로 병합하고 orphan people 제거 | DEV ONLY. 운영에는 자동 적용 금지 |

## Issue Registry

| ID | Problem Found | Why It Matters | Fix / Artifact | Verification Gate | Prod Rule |
| --- | --- | --- | --- | --- | --- |
| P2-001 | `member_profiles.profile_id`를 unique로 보면 실제 데이터와 충돌 | 한 로그인 계정이 여러 명부 row와 연결될 수 있음 | `20260430011000_phase2_member_profiles_profile_nonunique.sql` | `member_profiles.member_directory_id`만 unique, `profile_id`는 non-unique index | 운영 schema 생성 직후 반드시 포함 |
| P2-002 | `person_identifiers` source unique 기준이 너무 넓음 | 같은 source row에서 `legacy_profile`, `auth_user` 등 여러 identifier가 필요 | `20260430012000_phase2_person_identifiers_source_kind_unique.sql` | identifier kind별 row 공존 | 운영 schema 보정 후보 |
| P2-003 | 삭제된 `member_directory`를 가리키는 stale `group_members` 존재 | 없는 명부를 active membership처럼 보여주면 현재 소속이 왜곡됨 | `20260430021000...`, `20260501000000...` | `stale_active_group_member_memberships_not_ended = 0` | 자동 삭제 금지, ended history로 보존 |
| P2-004 | `group_members` 없이 `member_directory.group_name`에만 소속이 저장된 row 존재 | 박유나/신규 조원 같은 directory-only 소속이 Phase 2에서 누락될 수 있음 | `20260501000000_phase2_directory_membership_corrections.sql` | `directory_only_memberships_expected_vs_actual` missing 0 | backfill 필수 gate |
| P2-005 | `member_directory` trigger가 특정 컬럼 update만 감지 | 조편성/비활성화/복사 흐름에서 Phase 2 sync 누락 가능 | `20260501001000...`, `20260501003000...` | trigger column verify 통과 | 운영 dual-write 전 필수 |
| P2-006 | `pg_trigger_depth()` 때문에 nested legacy trigger 경로가 skip됨 | legacy trigger가 만든 2차 update가 Phase 2로 반영 안 될 수 있음 | `20260501002000_phase2_sync_trigger_depth_correction.sql` | nested write 후 consistency mismatch 0 | 운영 dual-write 전 필수 |
| P2-007 | `member_directory` delete 후 active orphan membership 발생 | 복사된 성도 삭제 시 새 모델에는 active 소속이 남아 목록 불일치 발생 | `20260502000000_phase2_member_directory_delete_sync.sql` | `verify_phase2_regrouping_write_flow...`의 `active_orphan_count = 0` | 운영 dual-write 전 필수 |
| P2-008 | `member_directory_unique_assignment` raw DB error 노출 | 조편성에서 같은 조/이름/전화번호 중복 저장 시 사용자에게 난해한 오류 노출 | `admin-web/src/app/regrouping/page.tsx` | 중복 저장 전 한국어 메시지로 차단 | 운영 UI 배포 후보 |
| P2-009 | 같은 사람의 여러 카드를 한 target group으로 동시에 이동 가능 | 한 사람을 같은 조에 중복 편성하는 입력 실수 발생 | `admin-web/src/app/regrouping/page.tsx` | 올리브새가족조장 중복 이동 저장 전 차단 | 운영 UI 배포 후보 |
| P2-010 | 조편성 header가 affiliation card 수를 성도 수로 표시 | 한 사람이 여러 조에 있으면 성도 수가 부풀려짐 | `admin-web/src/app/regrouping/page.tsx` | page-level count는 unique person 기준 | 운영 UI 배포 후보 |
| P2-011 | 비활성화 row가 조편성 화면에 노출 | 현재 조편성 작업 대상에 inactive history가 섞임 | `admin-web/src/app/regrouping/page.tsx` | regrouping fetch는 `is_active = true`만 | 운영 UI 배포 후보 |
| P2-012 | Phase 2 list/regrouping diagnostic이 church switch 때 흔들림 | stale React state 또는 church 미필터로 wrong warning 발생 | `admin-web/src/app/members/page.tsx`, `admin-web/src/app/regrouping/page.tsx` | diagnostics use explicit `churchId` argument | 운영 UI 배포 후보 |
| P2-013 | 성도 추가 자동완성이 다른 교회 사람을 후보로 표시 | 장전제일교회 `phase2test`가 Grace Church에서 선택 가능했음 | `admin-web/src/components/MemberModal.tsx` | current church active member만 후보 표시 | 운영 UI 배포 필수 |
| P2-014 | 자동완성 후보가 같은 사람의 부서/소속 row 수만큼 반복 | 사용자가 같은 사람을 여러 후보로 오해 가능 | `admin-web/src/components/MemberModal.tsx` | `person_id`, fallback `name+phone` dedupe | 운영 UI 배포 후보 |
| P2-015 | 성도 상세가 같은 `person_id`의 cross-church 정보를 섞어 보여줄 수 있음 | 기본 상세 화면에서 다른 교회 정보가 노출될 수 있음 | `admin-web/src/app/members/[id]/page.tsx` | detail Phase 2 panel scoped by current member church | 운영 UI 배포 후보 |
| P2-016 | 다중 소속 사람 상세 링크가 legacy directory row마다 다르게 보임 | 사용자는 한 사람으로 이해하지만 화면은 소속 row 중심 | Task: 사람 중심 상세 페이지 전환 | 별도 Phase 3 설계/QA | Phase 2 read-switch 전 방향성 확정 |
| P2-016A | 성도상세 “소속 정보” 카드가 legacy `_affiliations` 기준이라 같은 사람의 여러 상세 링크에서 row 중심으로 보일 수 있음 | Phase 2D 목표인 사람 중심 read 기준과 맞지 않고, 다중 소속 사람을 이해하기 어렵게 만듦 | `admin-web/src/app/members/[id]/page.tsx`: Phase 2 `memberships.status='active'` 기준 표시, Phase 2 연결 실패 시 legacy fallback | targeted lint 0 errors, dev consistency mismatch 0, multi-affiliation smoke 필요 | 운영 UI 배포 후보 |
| P2-017 | dev 데이터에서 서로 다른 성도가 같은 전화번호를 공유하는 오염 발견 | 전화번호만으로 자동 병합하면 오병합 가능 | `supabase/fix_minjaehong_phone_dev_2026-05-01.sql` | duplicate phone candidate 0 또는 검토완료 | 운영은 승인 후 별도 correction |
| P2-018 | dev 테스트 성도가 두 교회에 걸쳐 생성된 test pollution | 테스트 데이터가 실제 cross-church 정책 검증을 방해 | `supabase/fix_phase2test_cross_church_dev_2026-05-02.sql` | accidental Grace Church rows 0, refs 0 확인 후 삭제 | 운영 적용 금지 |
| P2-019 | dev master auth user와 profiles row 연결 문제 | 로그인은 Auth, 권한은 profiles를 같이 봄 | dev `profiles` row 보정 | 로컬 관리자 로그인 가능 | 운영 계정은 별도 확인, dev 보정 SQL 운영 금지 |
| P2-020 | Phase 2 테이블 RLS policy 없으면 진단 패널이 빈 상태 | 로그인은 되지만 새 테이블 read가 막힐 수 있음 | `20260430022000_phase2_read_policies.sql` | master/admin read smoke test | 운영 Phase 2 진단 전 필수 |
| P2-021 | 역할 모델이 `memberships.role`만으로 모든 권한을 해결하지 않음 | 조장/조원 역할과 admin/목회자/임원 권한은 범위가 다름 | Future role/permission policy task | 역할별 접근 시나리오 확정 | Phase 4 권한 모델로 분리 |
| P2-022 | 같은 교회 내 다른 부서 성도 열람 정책 미확정 | 등록 후보 검색과 개인정보 열람은 권한 수준이 달라야 함 | Future access policy task | 교회/부서/관리자별 read policy 결정 | broad read-switch 전 결정 |
| P2-023 | 고등부 -> 대학부 같은 부서 승급/일괄 이동 UX 없음 | DB는 가능하지만 운영자가 수동 비활성화/재등록해야 함 | Future bulk promotion task | bulk move/deactivate flow 설계 | 상업 서비스 안정화 범위 |
| P2-024 | 성도 전화번호 수정 후 `person_identifiers.phone`이 옛 번호로 남음 | 사람 찾기/중복 후보/identity audit가 오래된 번호를 계속 참조할 수 있음 | `20260503000000_phase2_identifier_phone_update_sync.sql` | `verify_phase2_member_directory_write_flow...`의 new phone 1, old phone 0 | 운영 dual-write 전 필수 |
| P2-025 | 온보딩 중 `profiles.person_id`가 기존 명부 사람으로 바뀌어도 `auth_user`/`legacy_profile` identifier가 임시 사람에 남음 | 로그인 계정이 실제 명부 사람과 다른 `people`에 붙어 있으면 앱 사용자와 명부 사람이 분리됨 | `20260503001000_phase2_profile_identifier_relink_sync.sql` | profile/onboarding verify의 auth_user 1, legacy_profile 1, profile-only member_profile 1 | 운영 dual-write 전 필수 |
| P2-026 | `profiles` 이름/전화번호 수정 후 profile-only `member_profiles` row가 stale 상태로 남음 | 성도 상세/계정 표시에서 예전 이름·전화번호가 보일 수 있음 | `20260503001000_phase2_profile_identifier_relink_sync.sql` | profile update verify의 member_profile_synced 1 | 운영 dual-write 전 필수 |
| P2-027 | SmartBatch upsert conflict target이 실제 `member_directory_unique_assignment`와 다름 | 대량 등록이 DB unique 제약과 어긋나 저장 실패 또는 잘못된 upsert를 만들 수 있음 | `admin-web/src/components/SmartBatchModal.tsx` | SmartBatch write-flow verify 통과, conflict target includes phone | 운영 UI 배포 후보 |
| P2-028 | SmartBatch 기존 성도 후보 검색이 inactive row를 포함하고 department alias를 잘못 읽음 | 대량 등록 시 비활성 이력 또는 부서 표시 누락으로 동일인 연결 판단이 흐려짐 | `admin-web/src/components/SmartBatchModal.tsx` | current church active rows만 후보, `department.name` 표시 | 운영 UI 배포 후보 |
| P2-029 | 조 삭제 후 active membership이 `group_id = NULL`로 남음 | 삭제된 조 소속이 현재 active처럼 보일 수 있고 read-switch 때 현재 소속이 왜곡됨 | `20260503002000_phase2_group_delete_sync.sql` | group lifecycle verify의 active null group 0 | 운영 dual-write 전 필수 |
| P2-030 | 조 삭제 후 active `member_directory.group_name`이 삭제된 조 이름을 계속 들고 있음 | legacy 명부와 Phase 2가 모두 삭제된 조 이름을 현재 소속처럼 보존할 수 있음 | `20260503002000_phase2_group_delete_sync.sql` | group lifecycle verify의 active deleted group_name rows 0 | 운영 dual-write 전 필수 |
| P2-031 | 부서 삭제 cascade 중 active memberships가 삭제될 department context를 유지하려 함 | 삭제된 부서의 소속이 active로 남거나 FK 충돌을 만들 수 있음 | `20260503003000_phase2_department_delete_sync.sql` | department lifecycle verify의 active null department 0, ended history 1 | 운영 dual-write 전 필수 |
| P2-032 | 부서 삭제 cascade 중 group delete trigger가 삭제 중인 `member_directory`를 update하여 FK 충돌 | department delete가 실패하거나 cascade 순서에 따라 Phase 2 sync가 깨질 수 있음 | `20260503004000_phase2_group_delete_department_cascade_fix.sql` | department lifecycle + group lifecycle verify 둘 다 통과 | 운영 dual-write 전 필수 |
| P2-033 | 교회/부서/조/주차 hard delete 경로가 운영 데이터 유실 위험을 가짐 | Phase 1/2 sync가 보존을 도와도 UI에서 영구 삭제를 허용하면 상업 서비스 운영 사고가 날 수 있음 | `20260503005000_p0_hard_delete_guardrails.sql`, admin/app code updates | P0 hard delete 경로 제거 또는 soft delete 전환 | Phase 2 운영 반영 전 필수 gate |
| P2-034 | `weeks.delete()`가 출석/기도/뉴스레터와 연결된 주차를 영구 삭제할 수 있음 | 주차 삭제 한 번으로 실제 예배 기록이 사라질 수 있음 | `GraceNoteRepository.deleteWeek()`를 `weeks.is_active=false`로 전환 | 주차 soft-disable 확인 | 운영 전 P0 |
| P2-035 | 공지/문의 hard delete가 이력 보존 정책과 맞지 않음 | 고객지원/공지 읽음 기록은 상업 서비스에서 추적 가능해야 함 | Future soft-delete task | `is_deleted/deleted_at` 도입 후 목록 숨김 | Phase 2 직후 또는 상용화 전 |
| P2-036 | 조 종료가 `오류가 발생했습니다`로 실패 | P0 soft-end 함수가 `memberships.ended_at`를 참조했지만 실제 컬럼은 `ends_at`라서 trigger update가 실패 | `20260503005000_p0_hard_delete_guardrails.sql` 수정 및 dev 함수 재적용 | 조 종료 update 후 `groups.is_active=false`, `groups.ended_at not null` | 운영 적용 전 migration 파일 기준 재검증 |
| P2-037 | 성도 비활성화 후 Phase 2 목록 진단 issue 1 발생 | `member_directory.is_active=false`가 linked `group_members`/`memberships`까지 종료하지 않아 비활성 명부에 active membership이 남음 | `20260504000000_p0_member_directory_inactive_sync_fix.sql` | inactive `member_directory` with active `memberships` = 0 | 운영 dual-write/P0 전 필수 |
| P2-038 | P0 이후 일부 Phase 2 write-flow 검증 SQL이 inactive 조/부서를 target으로 선택 | 검증 SQL이 실제 운영 후보 화면 기준과 달라 false negative를 만들 수 있음 | `verify_phase2_member_directory_write_flow`, `verify_phase2_regrouping_write_flow`, `verify_phase2_smart_batch_write_flow`, `verify_phase2_member_directory_trigger_columns` target을 active 부서/조로 제한 | 해당 4개 rollback verify 재실행 통과 | 운영 전 prod-safe verify 작성 시 active filter 포함 |
| P2-039 | 조편성에서 기존 성도 2명을 다른 조로 이동 후 legacy 111 / Phase 2 110 누락 1건 발생 | inactive `member_directory` row가 같은 조/이름/전화번호 unique 자리를 계속 잡아 `regroup_members()`가 실패할 수 있음 | `20260504001000_p0_member_directory_assignment_scope_fix.sql` | 이동 rollback 재현 후 legacy 111 / Phase 2 111 / issue 0 | Phase 2C smoke 재확인 필요 |
| P2-040 | 같은 조로 자기 자신을 첫 복사할 때 UI에서 즉시 차단되지 않음 | copy 동작에서 원본 카드를 duplicate 검사에서 제외해 첫 자기복사를 허용함 | `admin-web/src/app/regrouping/page.tsx` | 같은 조 자기복사는 드래그/복사 시점에 차단 | Phase 2C smoke 재확인 필요 |
| P2-041 | 중복 복사본을 제거한 뒤 저장하면 `member_directory_unique_assignment` raw DB error 발생 | inactive row가 `group_name`을 유지해 unique constraint를 계속 막음 | `20260504001000_p0_member_directory_assignment_scope_fix.sql` | 중복 제거 후 저장 성공 또는 active comparison issue 0 | Phase 2C smoke 재확인 필요 |
| P2-042 | 개인형 부서 성도 추가 필드에 배우자/자녀/결혼기념일 필드가 남음 | 부서 profile mode별 입력 UX가 맞지 않아 잘못된 가족 정보 입력을 유도 | `admin-web/src/components/MemberModal.tsx`, `admin-web/src/components/SmartBatchModal.tsx` | 개인형에서는 가족/결혼 필드 숨김 | Admin UI smoke 재확인 필요 |
| P2-043 | SmartBatch가 다른 교회 성도와 이름/전화번호가 같으면 중복 전화번호로 등록을 막음 | `check_phone_uniqueness()`가 전체 교회 범위에서 phone을 검사함 | `20260504001000_p0_member_directory_assignment_scope_fix.sql` | 다른 교회 같은 번호 등록 허용, 같은 교회 다른 사람 같은 번호는 차단 | SmartBatch smoke 재확인 필요 |
| P2-044 | 같은 교회 내 기존 성도 연동 시 전화번호가 자동 반영되지 않고 다른 번호로 저장 가능 | 연결 UI가 `person_id`만 반영하고 기존 row의 phone을 폼 row에 복사하지 않음 | `admin-web/src/components/SmartBatchModal.tsx` | 기존 성도 연결 시 후보 phone이 row phone으로 반영 | SmartBatch smoke 재확인 필요 |
| P2-045 | SmartBatch 분석 미리보기의 인원 수가 동일인 row를 감안하지 않고 row 수로만 표시 | 운영자가 “사람 수”와 “등록 row 수”를 혼동할 수 있음 | `admin-web/src/components/SmartBatchModal.tsx` | 동일인 연결 기준 실제 사람 수 표시, 필요 시 소속 입력 건수 보조 표시 | SmartBatch UI smoke 재확인 필요 |
| P2-046 | 교회 밖 전화번호 중복 후보를 관리하는 마스터용 reconciliation UI가 없음 | 교회 간 자동 연결/차단을 하지 않으면 운영자는 중복 후보를 별도로 점검해야 함 | Future master duplicate report task | master-only 중복 후보 리포트 설계 | Phase 3/운영 안정화 |
| P2-047 | 비활성화된 교회/부서/조/성도 row를 복구/관리하는 휴지통 UI가 없음 | hard delete를 막으면 운영자가 종료된 항목을 조회/복구할 관리 화면이 필요 | Future trash/archive management task | archived/inactive 목록, 복구 권한, audit log 설계 | Phase 3/상용화 전 |
| P2-048 | dev에서 한 교회 성도 row가 다른 교회 profile_id를 가리켜 다른 교회 기도제목이 노출됨 | profile 기반 기도조회가 다른 교회 개인정보를 상세 페이지에 섞어 보여줄 수 있음 | `20260504002000_phase2_church_scoped_identity_guardrails.sql`, `admin-web/src/app/members/[id]/page.tsx` | cross-church profile link blocked 1, detail profile query scoped by church | 운영 전 필수 |
| P2-049 | legacy `get_or_create_person_id()`가 교회 범위 없이 이름+전화번호로 person_id를 재사용 | 다른 교회 같은 이름/전화번호가 같은 사람으로 병합될 수 있음 | `20260504002000_phase2_church_scoped_identity_guardrails.sql` | cross-church same name/phone person_id가 서로 다름 | 운영 전 필수 |
| P2-050 | 성도명부 부서 query가 `profile_mode`를 가져오지 않아 부부형 필드가 숨겨짐 | 부부형 부서에서도 배우자/자녀/결혼기념일 입력이 불가능 | `admin-web/src/app/members/page.tsx` | 부부형 부서 선택 시 가족 필드 표시 | Admin UI smoke |
| P2-051 | 성도명부에서 기존 성도를 다른 조로 “추가”할 수 있어 명부와 조편성 책임이 섞임 | 같은 부서 사람 1명을 여러 조 row로 만드는 작업이 성도명부에서 발생하고 raw unique error로 이어짐 | `admin-web/src/components/MemberModal.tsx`; future person-centered roster split | 성도명부는 같은 부서 기존 사람 추가 차단, 조 복수 편성은 조편성 관리에서 처리 | Phase 2D/3 설계 |
| P2-052 | SmartBatch 미리보기 수가 실제 사람 수가 아니라 row 수 기준으로 보임 | 동일인 연결 후에도 운영자가 실제 등록 인원을 오해할 수 있음 | `admin-web/src/components/SmartBatchModal.tsx` | 동일인 연결 기준 사람 수 표시, 필요 시 소속 입력 건수 보조 표시 | SmartBatch UI smoke |
| P2-053 | SmartBatch에서 동일인 batch 연결 후 서로 다른 phone을 입력해도 저장이 허용됨 → Phase 2 누락 발생 | 같은 사람인데 phone이 달라 DB에 별개 person으로 저장되고 Phase 2 consistency가 깨짐 | `admin-web/src/components/SmartBatchModal.tsx`: `handleLinkSameNames`에서 첫 번째 phone으로 통일, 저장 전 phone 불일치 검증 추가 | 동일 batch_link_id 행들의 phone이 통일되고 불일치 시 저장 차단 | SmartBatch smoke 재확인 |
| P2-054 | SmartBatch에서 이미 명부에 있는 성도(DB 이름 중복/indigo)를 연결 없이 그냥 저장 가능 | 같은 부서 기존 성도가 중복 row로 추가되어 Phase 2 consistency 누락 발생 | `admin-web/src/components/SmartBatchModal.tsx`: indigo 상태에서 person_id 없으면 저장 차단(기존 로직 + 저장 시 재확인 강화) | DB 기존 성도 미연결 row는 저장 차단, 연결하거나 이름 구분자 추가 안내 | SmartBatch smoke 재확인 |
| P2-055 | Phase 2 목록 진단에서 `group_name='미정'`(조 미배정) row를 active로 세어 누락 2건 false positive 발생 | 조 미배정 성도는 Phase 2 group membership이 없는 것이 정상인데 진단이 이를 누락으로 오판 | `admin-web/src/app/members/page.tsx`, `admin-web/src/app/regrouping/page.tsx`: `refreshPhase2ListCheck` / `refreshPhase2RegroupingCheck`에서 `group_name != '미정'` 필터 추가 | 수정 후 dev 검증: old 기준 11건→9건, missing_count=0 확인 (`verify_phase2_diagnostic_fix_2026-05-04.sql`) | 해결완료 |
| P2-056 | SmartBatch에서 DB 연결된 성도를 이미 소속된 조 이름 또는 다른 조 이름으로 등록 시도 시 raw DB unique constraint 오류가 "알 수 없는 에러"로 노출 | 같은 조: upsert UPDATE 가능하나 no-op 혼란 / 다른 조: active row 중복 INSERT 시 constraint 위반. 두 경우 모두 raw error 노출 | `admin-web/src/components/SmartBatchModal.tsx`: 저장 전 검증에서 `person_id`가 `dbMatches`의 기존 row와 일치하면 같은 조·다른 조 각각 다른 안내로 차단 | 같은 조→"이미 ○○조에 소속, 명부 상세/조편성 관리에서", 다른 조→"현재 ○○조 소속, 조편성 관리에서 이동" 메시지 | 해결완료 |
| P2-057 | SmartBatch smoke 후 같은 교회 내부 dev 테스트 성도가 inactive row와 active row에서 서로 다른 `people`로 남음 | 같은 교회 같은 전화번호가 두 사람으로 남으면 identity audit가 빨갛게 뜨고 Phase 2C 완료 판단을 방해 | `fix_phase2c_smartbatch_duplicate_person_dev_2026-05-06.sql` | cleanup 후 `verify_phase2_consistency_dev_2026-04-30.sql`: missing/mismatch 0, same-church phone duplicate candidates 0 | DEV ONLY cleanup. 운영은 같은 현상 발견 시 별도 검토 후 correction 작성 |
| P2-058 | SmartBatch 브라우저 smoke 중 `setMatchingLoading is not defined` 런타임 에러 발생 | 기존 성도 후보 조회가 중단되어 동일인 연결 UI가 나타나지 않음 | `admin-web/src/components/SmartBatchModal.tsx`: 제거된 `matchingLoading` state의 남은 setter 호출 제거 | `npm run lint -- src/components/SmartBatchModal.tsx`: 0 errors | Phase 2C smoke 재확인 |
| P2-059 | Flutter 앱 로그인 후 `프로필 정보를 확인하고 있습니다...`에서 무한 로딩 | 로그인은 되었지만 `userProfileProvider`가 프로필 stream에서 null을 내보내면 라우터가 null 상태를 무한 로딩으로 처리함 | `lib/core/providers/data_providers.dart`: 초기 one-shot profile fetch 후 stream fallback. `lib/core/router/app_router.dart`: profile null은 무한 로딩 대신 인증/온보딩 흐름으로 이동 | `dart analyze lib/core/providers/data_providers.dart lib/core/router/app_router.dart`: error/warning 0, 기존 style info 6 | Flutter 앱 smoke 재확인 필수 |
| P2-060 | 개발환경 앱 smoke에서 SMS 인증 Edge Function 호출 실패(`Failed to fetch`)로 온보딩 이후 화면 검증 불가 | dev Supabase는 운영처럼 SMS 발송 환경이 준비되지 않을 수 있어 Phase 2C 앱 smoke가 인증 단계에서 막힘 | `lib/features/auth/presentation/screens/phone_verification_screen.dart`: dev Supabase URL(`eftdfxmdiefdduksdpwg`, localhost)에서만 보이는 “개발용 인증 건너뛰기” 추가. 기존 profiles row가 있는 계정만 `is_onboarding_complete=true` 처리 | `dart analyze phone_verification_screen.dart data_providers.dart app_router.dart`: error/warning 0, 기존 style info만 남음 | DEV ONLY helper. 운영 URL에서는 버튼 미노출 확인 필요 |
| P2-061 | Flutter 앱 smoke용 실제 권한 계정이 dev Auth에 없음 | `profiles`에는 smoke 대상 row가 있지만 `auth.users`가 없어 앱 로그인 후 실제 조장/관리자/일반 화면 smoke를 할 수 없음 | `supabase/fix_dev_auth_users_for_app_smoke_2026-05-06.sql`: 기존 `profiles.id`를 Auth UID로 사용하는 dev-only Auth/identity row 생성. Auth token text fields는 빈 문자열, password hash는 bcrypt cost 10으로 보정 | 적용 결과: dev Auth row 2개, identity_count 각 1, Auth password token API HTTP 200 | DEV ONLY. 운영 적용 금지, 비밀번호는 문서에 저장하지 않음 |
| P2-062 | P0 이후 성도 재활성화 검증 SQL의 기대값이 오래됨 | 비활성화 시 `group_name`을 비워 active assignment 자리를 release하도록 바뀌었으므로, `is_active=true`만으로는 조 membership이 복구되지 않는 것이 정상 | `verify_phase2_member_directory_write_flow_dev_2026-05-03.sql`: 재활성화 검증을 `is_active=true + group_name 재지정` 기준으로 수정 | 수정 후 active_memberships 1, inactive_memberships 0 | 운영 기능 변경 아님. prod-safe verify 작성 시 동일 기준 사용 |
| P2-063 | 조편성 화면은 Phase 2 표시 모델을 쓰지만 이미지/엑셀 내보내기는 원본 legacy row를 사용 | 화면에서는 숨긴 미편성/비활성 중복 row가 내보내기 파일에 다시 나타날 수 있음 | `admin-web/src/app/regrouping/page.tsx`: Excel export와 hidden `ExportTableView`도 `displayLocalMembers` 기준으로 전환 | `npm run lint -- src/app/regrouping/page.tsx`: 0 errors, consistency gate all mismatches 0 | 운영 UI 배포 후보 |
| P2-064 | 같은 `person_id`인데 소속 row마다 가족정보 표시가 다름 | 가족정보가 `people` 기준이 아니라 legacy `member_directory` row별로 흩어져 있어, 박민영처럼 일반조 row에는 가족정보가 있고 새가족조 row에는 비어 있을 수 있음 | `admin-web/src/app/members/page.tsx`, `admin-web/src/app/members/[id]/page.tsx`, `admin-web/src/app/regrouping/page.tsx`: 같은 person의 row 중 가족정보가 있는 값을 read model에서 대표값으로 보강 | targeted lint 0 errors, consistency gate all mismatches 0 | 운영 UI 배포 후보. 장기적으로 가족정보 저장 위치를 person/member_profile 중심으로 정리 필요 |
| P2-065 | 조편성 Kanban 초기 배치가 legacy `member_directory.group_name`과 조 이름 매칭에 의존 | 조 이름 변경/stale row/동명이 조가 있으면 Phase 2 현재 소속과 화면 배치가 다를 수 있음 | `admin-web/src/app/regrouping/page.tsx`: active `memberships.legacy_member_directory_id -> group_id`를 우선 사용하고 legacy group_name 매칭은 fallback으로 유지 | `npm run lint -- src/app/regrouping/page.tsx`: 0 errors, consistency gate all mismatches 0 | Phase 2D read-switch 운영 UI 배포 후보. 저장 write-flow는 아직 legacy + dual-write 유지 |
| P2-066 | 관리자 대시보드 성도 수/미배정 수가 legacy row 수 기준 | 한 사람이 여러 조에 있거나 inactive/unassigned row가 있으면 운영자가 실제 사람 수를 오해할 수 있음 | `admin-web/src/app/page.tsx`: active `memberships.person_id` distinct 기준으로 성도 수/미배정 수 계산, Phase 2 read 실패 시 legacy fallback | `npm run lint -- src/app/page.tsx`: 0 errors, consistency gate all mismatches 0 | Phase 2E read cleanup 운영 UI 배포 후보 |
| P2-067 | Flutter 앱 소속/역할 목록이 `group_members`만 읽음 | Phase 2D 이후 앱도 사람 중심 active membership을 기준으로 권한/조 선택을 해야 하지만, 저장 FK는 아직 legacy라 fallback이 필요 | `lib/core/providers/data_providers.dart`: `_fetchUserGroups()`가 active `memberships`를 먼저 읽고 기존 `group_members`를 fallback으로 사용 | `dart analyze data_providers/user_role_provider/models`: No issues, consistency gate all mismatches 0. Manual app smoke 필요 | Flutter Phase 2D read-switch 운영 후보. 출석/기도 write는 아직 legacy 유지 |
| P2-068 | Flutter 앱 조원 목록이 `member_directory.group_name`으로만 조회됨 | 조 이름 변경/stale legacy row가 있으면 앱 출석 대상 명단이 Phase 2 현재 소속과 달라질 수 있음 | `lib/core/repositories/grace_note_repository.dart`: `getGroupMembers()`가 active `memberships.legacy_member_directory_id`를 우선 사용하고 기존 `member_directory.group_name` 조회를 fallback으로 유지 | `dart analyze grace_note_repository`: no errors/warnings, existing style info only. Manual app smoke 필요 | Flutter Phase 2D read-switch 운영 후보. 출석/기도 save shape는 legacy 유지 |
| P2-069 | 관리자 출석 현황 화면이 현재 출석 대상 명단을 `member_directory` row 기준으로 읽음 | 조 이름 변경/stale legacy row가 있으면 주차별 추세, 상세 명단, 인사이트, export 대상이 Phase 2 현재 소속과 달라질 수 있음 | `admin-web/src/app/attendance/page.tsx`: current roster를 active `memberships.legacy_member_directory_id` 우선으로 구성하고 legacy `member_directory`는 fallback으로 유지 | `npx tsc --noEmit`: attendance page no errors, existing unrelated churches error remains. consistency gate all mismatches 0. Page lint still blocked by existing attendance lint debt | Admin attendance read cleanup 운영 후보. 출석 기록/저장 FK는 legacy `directory_member_id` 유지 |
| P2-070 | 관리자 출석 대시보드의 총원/출석률/인사이트/export 기준이 서로 다름 | 주차별 총원이 실제 person 변화처럼 보이고, UI insight와 다운로드 리포트 출석률이 다르게 보이며, 부부형 부서 정렬도 일관되지 않음 | 조사 결과: 예닮부 active rows 112 / active people 107. 화면 총원은 snapshot + current roster supplement 혼합이라 주차별로 흔들림. insight는 present만 출석, no-meeting 포함. export는 present+late 출석, no-meeting 제외 | Fix 전 별도 attendance dashboard audit 필요. 우선 라벨, 분모 정책, no-meeting/late 기준, 부부 정렬 기준을 확정해야 함 | 운영 전 P0/P1 UX correctness 후보. DB read-switch 자체와 별도 결함 |
| P2-071 | 출석률 분모가 제출 여부와 현재 roster 보충에 따라 흔들림 | 사람 중심 구조에서는 주차 기준 active person이 분모여야 한다. 단, 1월처럼 서비스를 나중에 도입하고 과거 출석을 후입력한 주차는 Phase 2 `starts_at`만으로 당시 부서 전체 인원을 복원하지 못함 | `admin-web/src/lib/attendanceMetrics.ts` 추가. denominator = week-date active distinct people + attendance snapshot people, retroactive week는 current active roster backfill 허용. numerator = present/late distinct people, no-meeting denominator excluded. `attendance/page.tsx` 카드/트렌드/인사이트/export에 적용 | `node --test src/lib/attendanceMetrics.test.ts`: 6 passed. `npm run lint -- src/lib/attendanceMetrics.ts`: passed. `npx tsc --noEmit`: attendance/metrics no errors, existing churches error remains. consistency mismatch 0 | Admin attendance dashboard 품질 보정 운영 후보 |
| P2-072 | 선택 주차 대상 숫자가 왜 바뀌는지 UI에서 설명되지 않음 | 운영자는 실제 person 수 변화인지, 과거 입력 보정인지 구분하기 어렵다 | `attendance/page.tsx`: 선택 주차 대상 산정 기준 패널 추가. active person, snapshot person, retroactive backfill count, 보정 포함 대상 일부 이름 표시 | Manual smoke 필요: 1월 예닮부 주차에서 대상 산정 기준이 표시되고 수치가 리포트/인사이트와 일관되는지 확인 | 운영 UI 배포 후보. 장기적으로 “대상 인원 변동 이유” 전용 리포트로 확장 가능 |
| P2-073 | retroactive backfill 조건이 너무 넓어 2월 정상 주차까지 current active roster로 보정됨 | 2월 1주처럼 active-window person이 이미 92명 있는데 snapshot 93/94명을 이유로 current active 107명까지 분모를 늘리면 실제 운영자가 보는 출석 대상이 왜곡됨 | `attendanceMetrics.ts`: current active roster backfill은 `activeWindowPeople = 0`이고 snapshot이 있는 과거 후입력 주차에만 적용. 일반 주차는 week-date active person만 분모로 사용. inactive/no-end membership도 active에서 제외 | `node --test src/lib/attendanceMetrics.test.ts`: 8 passed. 2월 1주/2주 smoke에서 107 강제 보정이 사라지는지 확인 | 운영 전 필수 UX correctness 후보 |
| P2-074 | 대상 숫자가 바뀌었을 때 “누가 들어오고 나갔는지”가 보이지 않음 | 사용자는 계산식보다 “전주 대비 5명이 누구고 왜 빠졌는지”가 필요하다 | `attendance/page.tsx`: 이전 주차 target person set과 선택 주차 target person set을 비교해 `전주 대비 추가/제외 N명: 이름...` 표시 | Manual smoke: 2월 1주→2주 전환 시 추가/제외 목록이 표시되는지 확인 | 이후 reason label(신규 등록/소속 종료/보정 포함)은 별도 고도화 후보 |
| P2-075 | 출석률 분모를 보정 알고리즘으로 추론하는 방식 자체가 불안정함 | 엑셀 출석표처럼 “그 주의 출석 대상 명단”이 먼저 있어야 하는데, 현재는 현재 roster/과거 membership/출석 제출 기록을 매번 조합해 분모를 추론한다 | `docs/superpowers/specs/2026-05-08-gracenote-attendance-roster-snapshot-design.md`: 주차+부서별 attendance roster snapshot 설계. 시스템 자동 생성 + 부서 관리자 이상 수동 수정 | dev migration/RPC/UI 구현 전 설계 승인 필요. 이후 분모는 snapshot included person 기준으로 전환 | Phase 2E attendance cleanup 선행 작업 |
| P2-076 | `profile_id`가 없는 directory-only 성도는 조편성 저장 후 조편성관리와 성도명부가 서로 다른 조를 보여줄 수 있음 | `sync_directory_to_group_members()`가 `profile_id is null`이면 return해서 `member_directory.group_name`은 새 조로 바뀌지만 active `group_members`/`memberships`는 옛 조에 남았다. 김보영 케이스에서 성도명부는 이동된 것처럼 보이고 조편성관리는 새가족부 카드가 남았다 | `20260513000000_phase3_regrouping_profileless_group_sync.sql`: `profile_id` 없이도 `member_directory.group_name` 기준으로 `group_members` active row를 생성/이동/비활성화. 기존 active directory row 재동기화 | `active_directory_group_member_group_mismatches = 0`, `active_membership_legacy_group_mismatches = 0`, Phase 2 consistency summary all 0. Manual smoke: 김보영 같은 directory-only 성도 이동 후 성도명부/조편성관리/진단 일치 | 운영 Phase 3 regrouping RPC 적용 전 필수 gate |
| P2-077 | 삭제/비활성 조의 과거 출석/기도 기록이 화면별로 다르게 보임 | 성도상세 기도 타임라인에는 삭제 조 기록이 보이지만, 출석 현황은 현재 active 조/현재 roster만 보면 과거 출석을 누락할 수 있음 | `20260516000000_phase3_group_active_period.sql`, `20260516001000_phase3_group_active_period_history_backfill.sql`: 조 active 기간 도입 및 attendance/prayer history 기반 backfill | 삭제테스트조 2026-05-03 smoke 통과. `attendance_rows_group_outside_active_period = 0` | 운영 전 필수. 생성 전 주차에는 숨기고, 기록이 있는 과거 주차에는 표시 |
| P2-078 | 사람 연결이 전혀 없는 attendance row가 출석 제출/인사이트 집계에 섞일 수 있음 | `person_id`, `directory_member_id`, `membership_id`가 모두 없는 row는 누가 출석했는지 증명할 수 없어 person 구조 통계와 리포트 신뢰도를 떨어뜨림 | `admin-web/src/app/attendance/page.tsx`: unlinked row는 warning으로만 표시하고 submitted/insight count에서 제외. `verify_attendance_unlinked_rows_detail_dev_2026-05-16.sql` 추가 | `attendance_rows_without_person_or_directory = 0`, detail SQL로 row 목록 확인 | 운영 전 blocking gate. 발견 시 자동 집계 금지, 운영자 확인 또는 cleanup 필요 |
| P2-079 | 제출 출석 row가 이미 생성된 자동 snapshot row에 반영되지 않음 | 같은 person/group/week에 자동 snapshot row가 먼저 있으면 `on conflict do nothing` 때문에 실제 제출 출석이 snapshot/리포트에 반영되지 않을 수 있음 | `20260516002000_attendance_snapshot_apply_submitted_person_rows.sql`: submitted attendance가 `auto_membership + unknown + reason null` row를 안전하게 update. manual row는 보존 | 삭제/비활성 조 제출 출석이 관리자 출석 현황과 리포트에 반영됨 | 운영 전 필수. snapshot integrity gate와 리포트 smoke로 확인 |


## Prod Execution Gates

운영 Phase 2 반영 전 최소 gate다.

| Gate | Command / Check | Expected |
| --- | --- | --- |
| G1 schema | `supabase/verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql` | 신규 테이블/필수 컬럼/PK/RLS/index 존재, all 0 |
| G2 backfill | `supabase/verify_phase2_people_memberships_backfill_dev_2026-04-30.sql`의 prod-safe 버전 | people/member_profiles/memberships missing 0 |
| G3 consistency | `supabase/verify_phase2_consistency_dev_2026-04-30.sql`의 prod-safe 버전 | 모든 mismatch 0, duplicate candidates 검토완료 |
| G4 dual-write | `supabase/verify_phase2c_dual_write_sync_dev_2026-04-30.sql`의 prod-safe 버전 | insert/update/delete 흐름 sync 유지 |
| G5 regrouping | `supabase/verify_phase2_regrouping_write_flow_dev_2026-05-02.sql`의 prod-safe 버전 | delete copy 후 active orphan 0 |
| G6 member directory writes | `supabase/verify_phase2_member_directory_write_flow_dev_2026-05-03.sql`의 prod-safe 버전 | 추가/수정/조변경/비활성화/재활성화 sync 유지 |
| G7 profile/onboarding writes | `supabase/verify_phase2_profile_onboarding_write_flow_dev_2026-05-03.sql`의 prod-safe 버전 | profile insert/update/person link sync 유지 |
| G8 SmartBatch writes | `supabase/verify_phase2_smart_batch_write_flow_dev_2026-05-03.sql`의 prod-safe 버전 | bulk insert/upsert sync 유지 |
| G9 group lifecycle | `supabase/verify_phase2_group_lifecycle_dev_2026-05-03.sql`의 prod-safe 버전 | rename 유지, delete 후 active null group 0 |
| G10 department lifecycle | `supabase/verify_phase2_department_lifecycle_dev_2026-05-03.sql`의 prod-safe 버전 | delete 후 active null department 0, missing directory active 0 |
| G11 UI smoke | 성도명부/상세/조편성/대량등록 diagnostics | selected church 기준 issues 0 또는 문서화된 예외만 |
| G12 manual QA | 성도 추가, 조 변경, 비활성화, 조편성 저장, 대량 등록 | legacy와 Phase 2 숫자가 함께 움직임 |
| G13 no dev-only apply | Dev-only files checklist | 운영 적용 목록에 dev-only SQL 없음 |
| G14 hard delete P0 | `2026-05-03-gracenote-hard-delete-audit.md`의 P0 항목 | 운영 UI/앱에서 교회/부서/조/주차/명부 hard delete가 직접 실행되지 않음 |
| G15 inactive member sync | inactive `member_directory` active membership query | 0 rows |
| G16 assignment/phone scope | `verify_p0_assignment_scope_and_phone_uniqueness_dev_2026-05-04.sql`의 prod-safe 버전 | inactive row는 active assignment를 막지 않고, cross-church same phone insert는 허용 |
| G17 church-scoped identity | `verify_phase2_church_scoped_identity_dev_2026-05-04.sql`의 prod-safe 버전 | 다른 교회 같은 이름/전화번호는 person_id 병합 안 됨, 다른 교회 profile link 차단 |
| G18 Phase 2D admin read smoke | 성도상세/성도명부/조편성/대시보드/출석 현황 | Phase 2 우선 표시, legacy fallback 가능, diagnostics issue 0 또는 문서화된 예외 |
| G19 Phase 2D Flutter read smoke | admin/leader/member/is_master 계정별 앱 진입, 기도/검색/출석/나의기도/저장기도 | 역할 화면 정상, 일반 조원 검색 범위 제한, 삭제 조 히스토리 주차별 노출, 출석/기도 저장 정상 |
| G20 Phase 2D Edge notification smoke | dev Edge Function dry-run log | `notify-event`, `notify-scheduler` dev 배포 완료. 둘 다 `verify_jwt=false`. `notify-scheduler` leader reminder dry-run에서 active `memberships` 우선 대상 산출 및 실제 발송 skip 확인. `notify-event` dry-run endpoint reachable, malformed/no-target notice는 `skipped=true` |
| G21 Phase 3 member write RPC | 성도 개별등록, AI 일괄등록, 상세 수정, 메모, 계정 연결, 조장 성도 추가/수정 | 직접 legacy write 없이 RPC 경유. Phase 2 summary all 0 |
| G22 Phase 3 lifecycle/archive | 성도 비활성, person+department 복구, 선택 조 복구, 부서/조 비활성 관리 | active 소속 세트가 의도대로 복구되고 duplicate assignment error 없음 |
| G23 Phase 3 regrouping save RPC | 조 이동/복사/부부 이동/신규 조/성도 추가/조 삭제 저장 | 성도명부와 조편성 화면이 같은 active memberships를 표시, profile-less mismatch 0 |
| G24 attendance snapshot | 관리자 출석 현황에서 snapshot 생성/명단 불러오기/추가/제외/출결 수정/리포트 추출 | `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql` all 0, 리포트 분모는 snapshot 기준 |
| G25 attendance/prayer snapshot fields | Flutter 출석/기도 저장 후 `person_id`, `membership_id`, `recorded_group_id`, `recorded_department_id` | `verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql` all 0 |
| G26 fresh migration dry-run | 운영 복제본 또는 fresh DB에 Order 1~48 순서 적용 | 2026-05-15 local fresh `supabase db reset` 통과. 2026-05-17 운영 복제본 dry-run에서 Order 1~48 적용 후 verification gate all PASS. 동일 교회 동일 전화번호 후보 0 |
| G27 pre-prod security lint | Supabase CLI advisory / RLS scan | `verify_app_config_rls_dev_2026-05-15.sql` all 0, `public.app_config` RLS enabled |
| G28 group active period history | 삭제/비활성 조의 과거 출석/기도 기록 | `attendance_rows_group_outside_active_period = 0`, 생성 전 주차에는 조 미노출, 기록 주차에는 조/출석/기도 노출 |
| G29 unlinked attendance rows | person/directory/membership이 모두 없는 attendance row | `attendance_rows_without_person_or_directory = 0`. detail SQL 결과가 있으면 운영 집계 전 cleanup 또는 수동 연결 |
| G30 submitted attendance snapshot apply | submitted attendance가 snapshot 자동 row에 반영되는지 | 삭제/비활성 조 또는 미제출 조 후제출 smoke에서 snapshot/리포트가 제출 출결을 표시 |

## Known Good Dev Verification

Latest known-good after `20260502000000_phase2_member_directory_delete_sync.sql`:

| Check | Result |
| --- | --- |
| people expected/actual | 137 / 137 |
| people missing | 0 |
| group_members memberships expected/actual | 123 / 123 |
| group_members missing | 0 |
| directory-only memberships expected/actual | 16 / 16 |
| directory-only missing | 0 |
| member_profiles expected/actual | 125 / 125 |
| member_profiles missing | 0 |
| active/inactive/stale/role mismatches | 0 |
| duplicate same-church phone candidates | 0 |
| regrouping delete-copy active orphan | 0 |
| member_directory write-flow phone update | new phone 1 / old phone 0 |
| profile/onboarding write-flow | profile insert/update/link all expected counts 1 |
| SmartBatch write-flow | bulk insert rows 2, active memberships 2, upsert role update 1 |
| group lifecycle | rename active 1, delete active null group 0, deleted group_name rows 0 |
| department lifecycle | active null department 0, active missing directory 0, ended history 1 |
| P0 object verification | columns/functions/triggers/indexes present |
| P0 soft-end verification | group active membership 0, department active membership 0, week is_active=false 확인, 임시 데이터 cleanup 0 |
| P0 group soft-end regression | 조 종료 후 `groups.is_active=false`, `groups.ended_at` set |
| P0 inactive member regression | 비활성 `member_directory` 중 active membership 보유 row 0 |
| member_directory write-flow | insert/update/group change/deactivate/reactivate expected counts all matched |
| regrouping write-flow | move/copy/delete-copy expected counts all matched |
| SmartBatch write-flow | bulk insert/upsert expected counts all matched |
| trigger column write-flow | group_name/role/is_active update expected counts all matched |
| assignment/phone scope | inactive assignment release 1, replacement active 1, cross-church same phone inserted 1 |
| church-scoped identity | cross-church same name/phone person split true, profile link blocked 1, cross-linked rows 0 |
| 2026-05-06 resync targeted lint | `SmartBatchModal`, `MemberModal`, `members`, `regrouping`, `members/[id]`: 0 errors, 24 existing warnings. `SmartBatchModal` 자체 경고는 0 |
| 2026-05-06 SmartBatch runtime fix lint | `npm run lint -- src/components/SmartBatchModal.tsx`: 0 errors |
| 2026-05-06 Flutter profile loading analyze | `dart analyze lib/core/providers/data_providers.dart lib/core/router/app_router.dart`: error/warning 0, 기존 style info 6 |
| 2026-05-06 Flutter dev SMS bypass analyze | `dart analyze lib/features/auth/presentation/screens/phone_verification_screen.dart lib/core/providers/data_providers.dart lib/core/router/app_router.dart`: error/warning 0, 기존 style info만 남음 |
| 2026-05-06 Flutter app smoke auth users | dev Auth users created for 2 smoke accounts, each linked to existing `profiles.id`, identity_count 1, Auth password token API HTTP 200 |
| 2026-05-06 Flutter app manual smoke | 출석 저장/재진입 유지 통과, 기도 저장/목록 표시 통과, 모임없는날 기능 정상. 주차 soft-disable는 현재 앱/관리자 UI에 삭제 기능이 없어 코드/DB gate로만 유지. 조원 active filter는 비활성 명부/조원 row가 앱 명단에 섞이지 않는지 보는 회귀 항목이며 별도 UI 동작 없음 |
| 2026-05-06 Phase 2C closeout gates | dual-write ready, SmartBatch rollback verify, regrouping rollback verify, member_directory write-flow verify, final consistency all passed |
| 2026-05-06 SmartBatch rollback verify | bulk insert rows 2, active memberships 2, upsert role update 1 |
| 2026-05-06 church-scoped identity verify | cross-church same name/phone split true, cross-church profile link blocked 1, cross-linked rows 0 |
| 2026-05-06 consistency after dev cleanup | people 148/148, group_members 133/133, directory-only 32/32, member_profiles 149/149, all mismatches 0, same-church phone duplicate candidates 0 |
| 2026-05-07 Phase 2D member detail read-switch | `npm run lint -- src/app/members/[id]/page.tsx`: 0 errors. `verify_phase2_consistency_dev_2026-04-30.sql`: people 148/148, group_members 133/133, directory-only 32/32, member_profiles 149/149, all mismatches 0 |
| 2026-05-07 Phase 2D member detail manual smoke | 다중 소속 사람을 서로 다른 legacy 상세 링크로 진입해도 같은 `people` 정보와 전체 active memberships가 표시됨. inactive/ended history는 현재 소속과 분리 표시됨 |
| 2026-05-07 Phase 2D member list person-count read-switch | `npm run lint -- src/app/members/page.tsx`: 0 errors, existing warnings only. 성도명부 상단/진단 숫자를 Phase 2 `person_id` 기준 실제 사람 수 우선 표시로 전환 |
| 2026-05-07 Phase 2D member list affiliation read | 성도명부 row의 소속 칸을 Phase 2 active `memberships` 기준으로 보강. 한 사람이 여러 현재 소속을 가지면 같은 row 안에 여러 부서/조 칩 표시. `verify_phase2_consistency_dev_2026-04-30.sql`: people 148/148, group_members 133/133, directory-only 32/32, member_profiles 149/149, all mismatches 0 |
| 2026-05-07 Phase 2D member list grouping UX | 전체 부서 보기의 그룹 모드는 부서별 섹션으로 표시. 특정 부서 보기의 그룹 모드는 조별 소속 row 기준으로 표시. `npm run lint -- src/app/members/page.tsx`: 0 errors. consistency gate all mismatches 0 |
| 2026-05-07 Phase 2D regrouping identity read prep | 조편성 화면의 통계/중복/삭제가능/진단 identity 기준을 Phase 2 `member_profiles.person_id` 우선으로 보강. write-flow는 legacy + dual-write 유지. `npm run lint -- src/app/regrouping/page.tsx`: 0 errors, existing warnings only. consistency gate all mismatches 0 |
| 2026-05-07 Phase 2D inactive/unassigned display policy | 성도명부 일반 화면은 active 소속이 있는 person의 inactive/ended row를 숨김. active 소속이 전혀 없는 person은 1행만 남김. 조편성 화면은 같은 person의 미편성 중복 카드를 1개로 정규화. targeted lint 0 errors, consistency gate all mismatches 0 |
| 2026-05-07 Phase 2D unassigned row refinement | active 조 소속이 있는 person은 성도명부 조별 모드의 미배정 row에서도 숨김. 박민영 smoke에서 다른 조 active 소속이 있는데 미배정 row가 남는 문제 보정. `npm run lint -- src/app/members/page.tsx`: 0 errors. consistency gate all mismatches 0 |
| 2026-05-07 Phase 2D regrouping display read model | 조편성 Kanban 표시 데이터는 Phase 2 `person_id`가 있는 경우 active group membership row를 우선 사용. legacy 저장 원본 `localMembers`는 유지해 write-flow는 변경하지 않음. `npm run lint -- src/app/regrouping/page.tsx`: 0 errors. consistency gate all mismatches 0 |
| 2026-05-07 Phase 2D regrouping export display model | 조편성 이미지/엑셀 내보내기도 화면과 같은 `displayLocalMembers` 기준을 사용하도록 보정. `npm run lint -- src/app/regrouping/page.tsx`: 0 errors. consistency gate all mismatches 0 |
| 2026-05-07 Phase 2D canonical family display | 같은 person의 여러 명부 row 중 일부에만 가족정보가 있어도 성도상세/성도명부/조편성에서는 가족정보 대표값을 보강해 표시. `npm run lint -- src/app/members/page.tsx src/app/regrouping/page.tsx src/app/members/[id]/page.tsx`: 0 errors. consistency gate all mismatches 0 |
| 2026-05-07 Phase 2D regrouping membership read source | 조편성 Kanban 초기 배치는 active `memberships.group_id`를 우선 사용하고, legacy `member_directory.group_name` 매칭은 fallback으로 유지. 저장 RPC/write-flow는 변경하지 않음. `npm run lint -- src/app/regrouping/page.tsx`: 0 errors. consistency gate all mismatches 0 |
| 2026-05-07 Phase 2E dashboard people count | 관리자 대시보드 성도 수/미배정 수를 active `memberships.person_id` distinct 기준으로 전환. Phase 2 read 실패 시 legacy count fallback 유지. `npm run lint -- src/app/page.tsx`: 0 errors. consistency gate all mismatches 0 |
| 2026-05-07 Flutter membership read-switch task 1 | 앱 `userGroupsProvider`가 active `memberships`를 우선 읽고 legacy `group_members`를 fallback으로 사용. `HOME=/private/tmp DART_SUPPRESS_ANALYTICS=true dart analyze lib/core/providers/data_providers.dart lib/core/providers/user_role_provider.dart lib/core/models/models.dart`: No issues found. consistency gate all mismatches 0 |
| 2026-05-07 Flutter group member read-switch task 2 | 앱 `getGroupMembers()`가 active `memberships.legacy_member_directory_id`를 우선 읽고 legacy `member_directory.group_name` 조회를 fallback으로 사용. `HOME=/private/tmp DART_SUPPRESS_ANALYTICS=true dart analyze lib/core/repositories/grace_note_repository.dart`: no errors/warnings, existing style info only. consistency gate all mismatches 0 |
| 2026-05-07 Admin attendance roster read cleanup | 관리자 출석 현황의 current roster를 active `memberships` 우선으로 읽고 legacy `member_directory` fallback 유지. 출석 기록 matching은 `attendance.directory_member_id` 그대로 유지. `npx tsc --noEmit --pretty false`: attendance page no errors, existing unrelated churches error remains. consistency gate all mismatches 0 |
| 2026-05-08 Admin attendance dashboard metric cleanup | 출석률 기준을 보정. 일반 주차는 week-date active distinct people만 분모로 사용하고, active-window가 0명인 과거 후입력 주차만 current active roster backfill 적용. no-meeting day 제외, `선택 주차 출석률` 라벨, 대상 산정/전주 대비 추가·제외 설명 패널, spouse/family-aware sort 적용. `node --test src/lib/attendanceMetrics.test.ts`: 8 passed. consistency gate all mismatches 0 |
| 2026-05-09 Admin attendance snapshot UI/export cleanup | 출석 대시보드 분모를 주차+부서 snapshot 기준으로 전환. 관리자가 조별 snapshot 구성원 추가/제외/출결 수정 가능. 미제출 조명단 일괄 불러오기 RPC 추가. 조장 제출본과 관리자 수정본 충돌 시 `덮어쓰기/병합하기/관리자 화면 유지`로 해결하며, 관리자 유지 선택은 snapshot member reason에 기록해 새로고침 후 재표시 방지. 리포트 export는 snapshot 기준, no-meeting 제외, 부부형 정렬, 같은 person 다중 조 출석 병합(`present` > `late` > `absent/unknown`) 적용. `node --test admin-web/src/lib/attendanceRosterSnapshots.test.ts`: 4 passed. `npx tsc --noEmit --pretty false`: attendance no errors, existing unrelated `churches/page.tsx:253` remains |
| 2026-05-09 Flutter prayer/search/attendance read refinement | 일반 조원 검색은 active membership 조 범위로 제한. 역할/소속 전환 시 검색 화면에서 기도소식으로 복귀. 기도소식/출석의 삭제 조는 active였던 주차 또는 기록이 있는 주차에만 보이고, 현재 active 조는 기본 표시 유지. `HOME=/private/tmp dart analyze ...`: 새 type error 없음, 기존 warning/info만 남음. `git diff --check`: passed |
| 2026-05-09 Edge Function notification target read-switch | `notify-event`, `notify-scheduler`의 조장/부서 대상 알림 조회를 active `memberships` 우선으로 전환하고 `group_members` fallback 유지. `git diff --check`: passed. secret literal scan passed. `deno` 미설치로 local deno check는 미실행 | Dev function deploy/dry-run smoke 필요 |
| 2026-05-13 Phase 3 regrouping profile-less sync gate | `profile_id = null`인 directory-only 성도도 조편성 저장 후 `member_directory`, active `group_members`, active `memberships`가 같은 조를 보도록 `sync_directory_to_group_members()`를 보정. 김보영 케이스 재현 후 dev DB에 migration 적용. `verify_phase2_consistency_summary_dev_2026-05-10.sql`: all checks 0, `active_directory_group_member_group_mismatches = 0`, `active_membership_legacy_group_mismatches = 0` | 운영 Phase 3 조편성 RPC 적용 직후 같은 gate를 반드시 실행 |
| 2026-05-15 Phase 3 group rename compatibility RPC | 부서관리에서 조 이름 변경 시 generic member upsert RPC가 성도 `profile_id`까지 다시 검증해 stale cross-church profile row에서 `Linked profile belongs to another church` 오류 발생. 조 이름 변경은 계정 연동 변경이 아니므로 `rename_member_directory_group_assignments()` 전용 RPC를 추가해 `group_name`만 갱신하도록 분리. dev DB에 남은 mismatch 1건 repair | `npm run lint -- src/app/departments/page.tsx src/lib/memberWriteRpc.ts`: 0 errors, existing hook warning only. `verify_phase2_consistency_summary_dev_2026-05-10.sql`: all checks 0. 운영 적용 시 조 이름 변경 전용 RPC migration 포함 필수 |
| 2026-05-15 Fresh local migration dry-run | 원격 `dev`에 origin UI/autosave 변경 + person migration 변경을 통합한 뒤, 로컬 fresh Supabase DB에 전체 migration을 처음부터 적용 | `supabase db reset`: migrations through `20260515001000_app_config_rls.sql` applied successfully. `verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql`: all 0. `verify_phase2_consistency_summary_dev_2026-05-10.sql`: all 0. `verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql`: all 0. `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`: all 0. `verify_app_config_rls_dev_2026-05-15.sql`: all 0 |
| 2026-05-15 Edge Function dry-run smoke | `notify-event`, `notify-scheduler` 알림 대상 read-switch 변경을 dev Edge Function에 재배포 | `deno check` 통과. `notify-event`, `notify-scheduler` 모두 `verify_jwt=false`. `notify-scheduler?task=leader_reminder&force=true&dry_run=true`에서 matched depts/groups/leaders 산출 후 send skip 확인. `notify-event?dry_run=true` endpoint reachable, no-target notice는 `skipped=true`. secret literal scan은 env var name만 검출 |
| 2026-05-15 Local prod-prep gate rerun | 운영 전 핵심 query-compatible gate를 local Supabase에 재실행 | `verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql`: all 0. `verify_phase2_consistency_summary_dev_2026-05-10.sql`: all 0. `verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql`: all 0. `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`: all 0. `verify_app_config_rls_dev_2026-05-15.sql`: all 0. `verify_phase2d_edge_notification_targets_dev_2026-05-09.sql`: all mismatch 0 |
| 2026-05-16 Attendance snapshot history hardening | 삭제/비활성 조의 과거 출석/기도 기록과 submitted attendance snapshot 반영을 보정 | dev DB migration 44~46 적용. `verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql`: all 0, `attendance_rows_without_person_or_directory=0`, `attendance_rows_group_outside_active_period=0`. 삭제테스트조 2026-05-03 smoke 통과 |
| 2026-05-16 Edge notification profile ownership filter | `member_profiles.profile_id`가 다른 `profiles.person_id`에 명시 연결된 경우 알림 대상으로 쓰지 않도록 보정 | dev data에서 stale legacy profile link 2건이 있었지만 잘못된 profile로 알림을 보내지 않도록 `notify-event`, `notify-scheduler`, `verify_phase2d_edge_notification_targets_dev_2026-05-09.sql` 보정. full psql gate all 0 |
| 2026-05-18 Edge scheduler person-count refinement | 등반 예정자 알림이 legacy `directory_member_id` 기준으로 출석 횟수를 세면 같은 사람이 여러 legacy row를 가진 경우 중복/누락 가능 | `notify-scheduler` 등반 후보 계산을 `attendance.person_id` 우선으로 전환하고, person 없는 과거 row만 `directory_member_id` fallback 사용. 조장 제외도 person 기준 우선. `deno check notify-event notify-scheduler verify-sms` 통과. 운영 복제본 `preprod-verify-gates-psql`: all PASS. `preprod-data-audit`: blocking/auto-repair 0 |
| 2026-05-18 Admin web prod build gate | 운영 적용 전 admin-web TypeScript/build 오류 제거 | `npx tsc --noEmit --pretty false`: PASS. `npm run build`: PASS after network-enabled Google Fonts fetch. targeted lint: 0 errors, existing warnings only. Node attendance tests: 12 passed |

## Pre-Prod UI Polish Backlog

운영 적용 전 기능 정확성 gate와 별개로, person 구조 전환 중 추가된 진단/관리 UI는 사용자용 디자인 정리가 필요하다.

| Area | Current Issue | Polish Direction |
| --- | --- | --- |
| 성도명부 상단 통계 | actual people / roster rows / active people가 디버깅 정보처럼 보임 | 운영 화면은 “성도 수” 중심으로 단순화하고 row/membership 수는 진단 접힘 영역으로 이동 |
| 성도명부 소속 칩 | 다중 부서/조 소속 칩이 정보는 정확하지만 화면이 복잡함 | 기본은 현재 부서/조 중심, 다중 소속은 보조 뱃지/툴팁/상세 패널로 표시 |
| 성도상세 소속/이력 패널 | Phase 2 현재 소속과 inactive 이력 정보가 기술적으로 노출됨 | “현재 소속”과 “과거 이력”을 사용자 언어로 재구성하고 source/debug 표시는 숨김 |
| 조편성 진단 | Phase 2/legacy 진단 숫자가 운영자에게 내부 DB 로그처럼 보일 수 있음 | 문제 없을 때는 숨기고, issue가 있을 때만 해결 가이드와 함께 표시 |
| 휴지통/비활성 관리 | person+department 복구와 선택 조 복구는 기능상 동작하지만 UX가 관리도구 느낌 | 항목별 “복구 대상 조 선택”을 더 명확한 단계형 UI로 정리 |
| 출석 snapshot 관리 | 명단 불러오기, 제외, 출결 토글, 조장 제출 충돌 해결 기능이 많음 | 핵심 조작은 카드 안에 유지하고 상세/충돌 해결은 접힘 패널 또는 모달로 분리 |
| SmartBatch 미리보기 | 사람 수/row 수/기존 성도 연결/조 선택이 한 화면에 몰림 | “분석 결과 → 연결 확인 → 조 배정 → 저장” 단계로 분리 |
| Flutter 소속/기도 표시 | active 소속 칩, 삭제 조 히스토리, 날짜/주차 문구가 화면별로 다르게 느껴질 수 있음 | 앱 톤에 맞춰 소속 히스토리와 주차 표기 규칙을 통일 |

## Future Logging Protocol

앞으로 새 문제가 나오면 다음 순서로 처리한다.

| Step | Required Action |
| --- | --- |
| 1 | 문제를 재현하거나 관찰한 화면/SQL/데이터 조건을 기록 |
| 2 | 원인을 legacy 구조, Phase 2 sync, UI state, 권한/RLS, test pollution 중 하나로 분류 |
| 3 | 수정 파일 또는 마이그레이션 파일을 명시 |
| 4 | 검증 SQL 또는 수동 QA gate를 추가 |
| 5 | 이 문서의 Issue Registry에 새 ID로 추가 |
| 6 | 운영 적용 여부를 `prod candidate`, `dev only`, `future task` 중 하나로 표시 |
| 7 | Notion 기술 의사결정 & 보고서에도 사람이 이해할 수 있는 버전으로 요약 |

이 규칙을 따르면 “개발 서버에서 고친 문제를 운영 반영 때 빼먹는 문제”를 줄일 수 있다. 단, 최종 확신은 운영 적용 직전의 fresh prod dump, prod-safe verification SQL, 적용 목록 대조로만 확보한다.
