# 개발 가이드라인 (Security & Environment)

본 프로젝트는 보안 정보 유출 방지와 외부 환경 변화에 유연하게 대응하기 위해 **환경 변수(.env)** 시스템을 사용합니다.

## 1. 초기 설정

1.  프로젝트 루트에 `.env` 파일을 생성합니다.
2.  `.env.example` 파일의 내용을 복사하여 `.env`에 붙여넣습니다.
3.  실제 서비스에 필요한 `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GEMINI_API_KEY` 등을 입력합니다.

## 2. 보안 수칙

-   **절대 주의**: `.env` 파일은 실제 비밀번호와 API 키를 포함하고 있으므로 **절대 Git에 커밋하지 마세요.**
-   이미 `.gitignore`에 `.env*` 패턴이 추가되어 있어 실수로 올라가는 것을 방어하고 있습니다.
-   새로운 환경 변수가 필요할 경우 `.env.example`에도 해당 변수명을 추가하여 다른 개발자들과 공유하세요.

## 3. 코드에서 사용법

`AppConstants` 클래스를 통해 접근합니다.

```dart
// Supabase URL 가져오기
final url = AppConstants.supabaseUrl;
```

## 4. 빌드 시 주입 (CI/CD 및 배포)

배포 환경(Codemagic, GitHub Actions 등)에서는 다음과 같이 빌드 옵션을 통해 값을 주입할 수도 있습니다. `AppConstants`는 이 값도 하위 호환성으로 지원합니다.

```bash
flutter build apk --dart-define=SUPABASE_URL=https://...
```
