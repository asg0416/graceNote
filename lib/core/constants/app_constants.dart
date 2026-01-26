class AppConstants {
  static const String appName = 'Grace Note';
  
  // --dart-define 옵션을 통해 빌드 시점에 주입받습니다.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eejqiddsdovrabcsxznu.supabase.co',
  );
  
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY', // 보안을 위해 비워두거나 빌드 시 주입
  );
  
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'YOUR_GEMINI_API_KEY',
  );

  static const String appVersion = '1.2.7+7';
 // [NEW] Current app version
}
