# IAM 설문 빌더 설계 문서

**날짜:** 2026-04-20  
**범위:** 관리자웹 설문 빌더 + 응답 결과 페이지 + Flutter 앱 설문 렌더러  
**접근법:** A (기존 테이블 컬럼 확장)  
**하위 호환성:** 불필요 (기존 rating/comment 데이터 폐기)

---

## 1. DB 스키마

### 1-1. `in_app_messages` 변경

```sql
ALTER TABLE public.in_app_messages
  ADD COLUMN survey_questions jsonb;

-- survey_questions 구조 (survey 타입일 때만 사용)
-- [
--   {
--     "id": "uuid-v4",
--     "type": "star_rating" | "radio" | "checkbox" | "text",
--     "text": "질문 내용 (최대 200자)",
--     "required": true | false,
--     "options": ["옵션1", "옵션2"]   -- radio/checkbox만 사용 (최대 8개, 각 최대 50자)
--   },
--   ...  최대 6개
-- ]
```

### 1-2. `iam_survey_responses` 변경

```sql
-- rating, comment 제거 → answers jsonb로 교체
ALTER TABLE public.iam_survey_responses
  DROP COLUMN rating,
  DROP COLUMN comment,
  ADD COLUMN answers jsonb NOT NULL,
  ADD CONSTRAINT answers_is_array CHECK (jsonb_typeof(answers) = 'array');

-- answers 구조
-- [
--   { "question_id": "uuid-v4", "value": 4 },                        -- star_rating
--   { "question_id": "uuid-v4", "value": "선택한 옵션" },              -- radio
--   { "question_id": "uuid-v4", "value": ["옵션1", "옵션3"] },         -- checkbox
--   { "question_id": "uuid-v4", "value": "주관식 텍스트" }             -- text
-- ]
```

### 1-3. RLS 변경 없음

기존 정책 그대로 유지:
- `Survey responses insert own`: `WITH CHECK (user_id = auth.uid())`
- `Survey responses select own`: `USING (user_id = auth.uid())`
- `survey_master_all`: 마스터 전체 권한
- 관리자 응답 조회: `IAM church admin manage` 정책으로 커버

---

## 2. 관리자웹 - 설문 빌더 (IamForm.tsx)

### 2-1. UI 진입점

- `type = 'survey'` 선택 시 기존 "콘텐츠" 섹션(본문/슬라이드 에디터) 숨김
- `use_slides` 토글 숨김 (survey 타입은 항상 질문 슬라이드 방식)
- 대신 **SurveyBuilder** 컴포넌트 표시

### 2-2. SurveyBuilder 컴포넌트

**질문 카드 구조:**
```
┌──────────────────────────────────┐
│ Q1  [타입 선택 ▼]        [🗑 삭제] │
│                                  │
│ 질문 내용 _____________________  │
│                                  │
│ [radio/checkbox 타입 시]          │
│  • 옵션1 ________  [x]           │
│  • 옵션2 ________  [x]           │
│  + 옵션 추가                      │
│                                  │
│ ☐ 필수 질문                       │
└──────────────────────────────────┘
[+ 질문 추가]
```

**타입별 동작:**
- `star_rating`: 별점 1~5 미리보기만 표시, 추가 설정 없음
- `radio` / `checkbox`: 옵션 목록 (최소 2개, 최대 8개)
- `text`: 플레이스홀더 텍스트 입력 필드

**제약 조건:**
- 질문 최대 6개 (초과 시 "질문 추가" 버튼 비활성)
- radio/checkbox 옵션 최대 8개
- 질문 텍스트 최대 200자
- 옵션 텍스트 최대 50자
- 질문 최소 1개 이상 있어야 저장 가능

### 2-3. 앱 미리보기 (AppPreview)

- survey 타입 시 미리보기에 첫 번째 질문 렌더링
- 질문 타입에 맞는 입력 UI 미리보기 표시 (실제 입력 불가)
- "Q1 / 총 N개" 슬라이드 위치 표시

### 2-4. 보안 (관리자웹)

- 저장 전 질문 텍스트 / 옵션 텍스트 DOMPurify sanitize (XSS 방지)
- 질문 `id`는 `crypto.randomUUID()` 생성 (예측 불가)
- 클라이언트에서 6개 / 200자 / 50자 제한 적용
- 서버 제출 시 배열 길이 초과 여부 validate 함수에서 추가 검증

---

## 3. 관리자웹 - 응답 결과 페이지 (responses/page.tsx)

### 3-1. 페이지 구조 (2탭)

```
[집계 요약]  [개별 제출 목록]
```

### 3-2. 집계 요약 탭

- 총 응답자 수 / 완료율 헤더
- 질문별 카드:
  - `star_rating`: 평균 점수 + 1~5점 분포 바 차트
  - `radio`: 옵션별 선택 비율 가로 바 차트
  - `checkbox`: 옵션별 선택 횟수/비율 바 차트
  - `text`: 최신 응답 텍스트 목록 (페이지네이션)
- 차트는 Tailwind CSS 기반 순수 바 차트 (외부 차트 라이브러리 미사용)

### 3-3. 개별 제출 목록 탭

- 제출일시 + 응답자명(프로필) 행 목록
- 행 클릭 시 슬라이드오버(사이드패널)로 해당 제출의 질문별 답변 전체 표시
- 응답자명은 마스터/교회 어드민만 열람 가능 (RLS)

---

## 4. Flutter 앱 - 설문 렌더러

### 4-1. 화면 흐름

```
IamCard (title + type badge)
        ↓
IamSurveyWidget (PageView 기반, 스와이프 비활성)
  [Q1] 질문 + 입력 UI → [이전] [다음]
  [Q2] 질문 + 입력 UI → [이전] [다음]
  ...
  [마지막] → [이전] [제출하기]
        ↓
제출 완료 → onSubmitted() → IAM 자동 dismiss
```

### 4-2. 질문 타입별 위젯

| 타입 | Flutter 위젯 |
|------|------------|
| `star_rating` | 기존 별점 Row (GestureDetector + Icon) |
| `radio` | RadioListTile 리스트 |
| `checkbox` | CheckboxListTile 리스트 |
| `text` | TextField (maxLines: 4, maxLength: 500) |

### 4-3. 네비게이션

- 이전/다음 버튼 명시적 제공 (자동 전환 없음)
- 필수 질문 미응답 시 다음 이동 차단 + SnackBar 안내
- PageController로 슬라이드 전환 (기존 IamCard PageView와 별도)
- 진행 상태: "Q2 / 4" 텍스트 또는 선형 인디케이터

### 4-4. 제출

- 모든 필수 질문 응답 완료 시 "제출하기" 활성화
- `answers` 배열 구성 후 `iam_survey_responses`에 insert
- 기존 `iamSurveyAnsweredProvider` 재활용 (기응답자 자동 dismiss)

---

## 5. 보안 체크리스트

| 항목 | 처리 방법 |
|------|----------|
| XSS | 관리자웹 저장 전 DOMPurify sanitize, 앱은 Text 위젯(HTML 미렌더링) |
| 입력 길이 초과 | DB CHECK constraint + 클라이언트 maxLength 이중 검증 |
| 질문 구조 위변조 | 제출 시 question_id가 해당 메시지 survey_questions에 존재하는지 서버에서 검증 |
| 중복 제출 | UNIQUE(message_id, user_id) 유지 |
| 타인 응답 열람 | RLS select own 유지, 집계 조회는 어드민 전용 정책 |
| 대량 스팸 | UNIQUE constraint로 1인 1회 보장 |
| SQL injection | Supabase 클라이언트 파라미터 바인딩으로 원천 차단 |
| jsonb 구조 오염 | answers_is_array CHECK constraint + 앱/웹 양측 validate |

---

## 6. 파일 변경 목록 (예상)

| 파일 | 변경 내용 |
|------|----------|
| `supabase/migrations/새파일.sql` | survey_questions 컬럼 추가, rating/comment 제거 |
| `admin-web/src/app/in-app-messages/IamForm.tsx` | SurveyBuilder 컴포넌트 추가, 미리보기 survey 렌더링 |
| `admin-web/src/app/in-app-messages/[id]/responses/page.tsx` | 2탭 구조, 집계 차트, 개별 제출 상세 |
| `lib/core/models/in_app_message.dart` | SurveyQuestion 모델 추가 |
| `lib/core/widgets/iam_survey_widget.dart` | 완전 재작성 (다중 질문 PageView) |

---

## 7. 구현 순서

1. DB 마이그레이션
2. Flutter 모델 업데이트
3. 관리자웹 SurveyBuilder 컴포넌트
4. 관리자웹 AppPreview survey 렌더링
5. 관리자웹 responses 페이지 리빌드
6. Flutter IamSurveyWidget 재작성
7. 보안 검증 및 테스트
