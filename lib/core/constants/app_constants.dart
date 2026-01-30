import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get appName => _getEnv('APP_NAME', 'Grace Note');
  
  static String get supabaseUrl => _getEnv(
    'SUPABASE_URL', 
    'https://eejqiddsdovrabcsxznu.supabase.co'
  );
  
  static String get supabaseAnonKey => _getEnv('SUPABASE_ANON_KEY', '');
  
  static String get geminiApiKey => _getEnv('GEMINI_API_KEY', '');

  static const String appVersion = '1.2.7+7';

  // [Helper] .env -> Dart-Define(String.fromEnvironment) 순서로 안전하게 값을 가져옵니다.
  static String _getEnv(String key, String defaultValue) {
    try {
      // 1. .env 파일에 값이 있다면 우선 사용
      if (dotenv.isInitialized && dotenv.env.containsKey(key)) {
        final value = dotenv.env[key];
        if (value != null && value.isNotEmpty) return value;
      }
    } catch (_) {
      // dotenv 관련 에러 무시
    }

    // 2. 빌드 시 주입된 --dart-define 값 확인
    const fromEnv = String.fromEnvironment;
    final value = fromEnv(key);
    if (value.isNotEmpty) return value;

    // 3. 최종 기본값 반환
    return defaultValue;
  }
}
