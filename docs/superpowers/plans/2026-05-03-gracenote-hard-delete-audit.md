# GraceNote Hard Delete Audit

> Purpose: 운영 반영 전에 실제 서비스 데이터를 영구 삭제하는 경로를 전수조사하고, 어떤 삭제를 막거나 soft delete로 바꿔야 하는지 결정하기 위한 기준 문서다.

## 결론

지금 전수조사를 먼저 하는 것이 맞다. 단, 모든 hard delete를 한 번에 수정하면 범위가 너무 커져서 Phase 2 검증 자체가 흔들릴 수 있다.

따라서 운영 반영 전에는 `P0` 경로부터 차단한다. `P1`은 상용 서비스 안정화 전까지 soft delete 정책으로 전환하고, `P2`는 인증 토큰/임시 인증번호처럼 영구 삭제가 정상인 데이터로 분리한다.

## 분류 기준

| Level | 의미 | 운영 전 처리 |
| --- | --- | --- |
| P0 | 교회/부서/조/주차/성도 소속처럼 삭제하면 실제 사용 데이터가 날아가는 경로 | Phase 2 운영 반영 전 차단 또는 soft delete 전환 |
| P1 | 공지/문의처럼 서비스 기록이지만 즉시 Phase 2 구조를 깨지는 않는 경로 | 상용화 전 soft delete 또는 보존 정책 확정 |
| P2 | 푸시 토큰, SMS 인증번호, 중복 방지 로그처럼 임시/파생 데이터 | hard delete 유지 가능 |
| DEV ONLY | 개발 서버 보정, 테스트 데이터 정리, 수동 SQL | 운영 적용 금지 |

## 핵심 원칙

삭제 버튼이 “정말 삭제”를 뜻하면 안 되는 데이터가 있다.

사람이 이해하는 삭제는 대부분 “현재 화면에서 안 보이게 함”이다. DB에서는 과거 출석, 기도제목, 소속 이력, 문의 기록을 보존해야 한다. 그래서 운영 서비스에서는 `is_active=false`, `ended_at`, `deleted_at`, `archived_at` 같은 상태값을 우선 사용한다.

## 삭제 경로 인벤토리

| 경로 | 대상 | 현재 동작 | 위험 | 권장 처리 | 우선순위 |
| --- | --- | --- | --- | --- | --- |
| `admin-web/src/app/churches/page.tsx` | `churches` | 교회 hard delete | 교회 하위 부서/조/성도/공지/문의가 연쇄 삭제될 수 있음 | 운영에서는 삭제 버튼 제거 또는 `archived_at` 기반 보관 처리 | P0 |
| `admin-web/src/app/departments/page.tsx` | `departments` | 부서 hard delete | 부서 하위 조/명부/소속 이력이 삭제 또는 ended 처리됨. 현재 Phase 2 sync 보정은 했지만 실제 운영 UX로는 위험 | 부서 `is_active`/`ended_at` 추가 후 비활성화로 전환 | P0 |
| `admin-web/src/app/departments/page.tsx` | `groups` | 조 hard delete | 현재 Phase 1/2로 출석/기도/소속 이력 유실은 막았지만, 운영자가 실수로 현재 조를 제거할 수 있음 | 조 삭제 대신 `is_active=false`, `ended_at` 전환. 진짜 삭제는 빈 테스트 조만 허용 | P0 |
| `admin-web/src/app/regrouping/page.tsx` | `groups` | 조편성 저장 시 로컬 상태에 없는 조 hard delete | 조편성 화면 실수로 조가 영구 삭제될 수 있음 | 조편성 저장에서는 group hard delete 금지, inactive 처리 또는 명시적 “조 종료” flow로 분리 | P0 |
| `lib/core/repositories/grace_note_repository.dart` | `weeks` | 주차 hard delete | `attendance`, `prayer_entries`, `newsletters`와 연결되어 출석/기도/주보 데이터가 연쇄 삭제될 수 있음 | 주차 삭제 금지. 필요 시 `weeks.is_active=false` 또는 “예배 없음” 상태로 처리 | P0 |
| `admin-web/src/app/regrouping/page.tsx` | `member_directory` | 조편성 복사/제거 흐름에서 hard delete | Phase 2 orphan은 막았지만, 명부 이력 자체가 사라짐 | 복사 카드 제거도 기본은 `is_active=false`/`left_at` 처리. 테스트/임시 row만 hard delete 허용 여부 검토 | P0 |
| `admin-web/src/app/members/page.tsx` | `member_directory` | 현재는 대부분 `is_active=false` | 올바른 방향 | 유지. hard delete로 되돌리지 않기 | 유지 |
| `admin-web/src/app/notices/page.tsx` | `notices` | 공지 hard delete | 읽음 기록 `notice_reads`가 같이 사라질 수 있음 | `is_deleted`, `deleted_at` 추가 후 숨김 처리 | P1 |
| `lib/features/home/presentation/screens/inquiry_screen.dart` | `inquiries` | 문의 hard delete | 사용자/관리자 상담 기록과 답변이 사라짐 | `is_deleted_by_user`, `deleted_at` 또는 사용자 화면 숨김 처리 | P1 |
| `lib/core/repositories/grace_note_repository.dart` | `no_meeting_days` | 예배 없음 일정 hard delete | 출석/기도 원본 데이터는 아니고 일정 override 성격 | 취소 동작으로 hard delete 유지 가능. 단 audit log가 필요하면 soft delete | P2 또는 P1 |
| `lib/core/repositories/grace_note_repository.dart` | `prayer_interactions` | 기도하기/보관하기 toggle hard delete | 사용자 반응 토글 데이터 | hard delete 유지 가능 | P2 |
| `supabase/functions/*` | `phone_verifications`, push token류 | 인증번호/죽은 토큰 정리 | 임시/파생 데이터 | hard delete 유지 가능 | P2 |
| `cleanup_future_data.sql`, `fix_data_integrity.sql`, dev 보정 SQL | 여러 테이블 | 수동 hard delete | 운영에서 잘못 실행하면 위험 | 운영 자동 적용 금지. 필요 시 별도 prod correction 파일로 재작성 | DEV ONLY |

## 운영 전 P0 작업 목록

1. `churches` 삭제 버튼을 운영 UI에서 막는다. 교회는 최상위 tenant라서 hard delete 대상이 아니다.
2. `departments`에 종료/비활성화 상태를 추가하고, 부서 삭제 버튼을 “부서 종료”로 바꾼다.
3. `groups` 삭제를 “조 종료”로 바꾼다. 이미 `groups.is_active`가 있으므로 UI와 쿼리 필터부터 전환한다.
4. `regrouping` 저장 flow에서 삭제된 조를 DB에서 지우지 않고 inactive 처리한다.
5. `weeks.delete()` 호출을 제거하거나 관리자 확인이 필요한 비활성화 flow로 바꾼다.
6. 조편성의 `member_directory.delete()`가 진짜 임시 복사 row만 지우는지 재검토하고, 기본값은 `is_active=false`로 맞춘다.

## 2026-05-04 P0 회귀 이슈

조 종료와 성도 비활성화는 단순히 UI에서 삭제 버튼을 바꾸는 것으로 끝나지 않는다. DB trigger가 기존 legacy 테이블과 Phase 2 테이블을 같이 정리해야 한다.

| 이슈 | 원인 | 처리 | 운영 전 확인 |
| --- | --- | --- | --- |
| 조 종료 시 `오류가 발생했습니다` | P0 trigger 함수가 `memberships.ended_at`를 참조했지만 실제 컬럼은 `memberships.ends_at` | `20260503005000_p0_hard_delete_guardrails.sql` 함수 수정 및 dev 함수 재적용 | 조 종료 후 `groups.is_active=false`, `groups.ended_at not null` |
| 성도 비활성화 후 Phase 2 목록 진단 issue 1 | `member_directory.is_active=false`가 linked `group_members`/`memberships`를 inactive/ended 처리하지 않음 | `20260504000000_p0_member_directory_inactive_sync_fix.sql` 추가 및 dev 함수 재적용 | inactive `member_directory` with active `memberships` = 0 |

## 운영 전에는 아직 하지 않아도 되는 작업

공지와 문의 soft delete는 중요하지만 Phase 2 사람/소속 구조 자체를 깨는 축은 아니다. 다만 상용 서비스에서는 고객지원 기록과 공지 이력을 보존해야 하므로 Phase 2 운영 반영 직후 또는 상용화 전 별도 작업으로 처리한다.

## 앞으로의 기록 규칙

hard delete 경로가 새로 발견되면 다음 네 가지를 반드시 남긴다.

| 항목 | 기록 내용 |
| --- | --- |
| 대상 테이블 | 어떤 데이터가 삭제되는지 |
| 사용자 의미 | 사용자가 삭제라고 이해하는 대상이 무엇인지 |
| 실제 DB 영향 | 어떤 하위 데이터가 같이 사라지는지 |
| 운영 방침 | hard delete 유지, soft delete 전환, 삭제 버튼 제거 중 하나 |

이 문서는 Phase 2 운영 반영 최종 실행표의 hard delete gate와 함께 관리한다.
