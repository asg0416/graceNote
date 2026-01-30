import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get appName => dotenv.get('APP_NAME', fallback: 'Grace Note');
  
  // 1. Dotenv 우선, 2. Dart-Define(빌드타겟) 순서로 값을 가져옵니다.
  static String get supabaseUrl => dotenv.get(
    'SUPABASE_URL', 
    fallback: const String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://eejqiddsdovrabcsxznu.supabase.co')
  );
  
  static String get supabaseAnonKey => dotenv.get(
    'SUPABASE_ANON_KEY',
    fallback: const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '')
  );
  
  static String get geminiApiKey => dotenv.get(
    'GEMINI_API_KEY',
    fallback: const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '')
  );

  static const String appVersion = '1.2.7+7';
}
