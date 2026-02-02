import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // [IMPORTANT] String.fromEnvironment must be used with 'const' to work correctly in Flutter Web
  static const String _envAppName = String.fromEnvironment('APP_NAME', defaultValue: 'Grace Note');
  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://eejqiddsdovrabcsxznu.supabase.co');
  static const String _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const String _envGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static String get appName => _getEnv('APP_NAME', _envAppName);
  
  static String get supabaseUrl => _getEnv('SUPABASE_URL', _envSupabaseUrl);
  
  static String get supabaseAnonKey => _getEnv('SUPABASE_ANON_KEY', _envSupabaseAnonKey);
  
  static String get geminiApiKey => _getEnv('GEMINI_API_KEY', _envGeminiApiKey);

  static const String appVersion = '1.4.1';

  static String _getEnv(String key, String defaultValue) {
    try {
      if (dotenv.isInitialized && dotenv.env.containsKey(key)) {
        final value = dotenv.env[key];
        if (value != null && value.isNotEmpty) return value;
      }
    } catch (_) {}
    return defaultValue;
  }
}
