import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/router/app_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/services/ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grace_note/core/providers/settings_provider.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grace_note/core/services/update_notifier.dart';
import 'package:grace_note/core/services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  // Initialize Environment Variables
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("DEBUG: .env load success");
  } catch (e) {
    debugPrint("DEBUG: .env load skipped/failed (expected in production)");
  }

  // Debug Constants (Wrap in try-catch to prevent initialization crash)
  try {
    debugPrint("DEBUG: Supabase URL target: ${AppConstants.supabaseUrl}");
    final keyLen = AppConstants.supabaseAnonKey.length;
    debugPrint("DEBUG: Supabase Key length: $keyLen");
    if (keyLen == 0) {
      debugPrint("WARNING: Supabase Anon Key is EMPTY. Auth will not work.");
    }
  } catch (e) {
    debugPrint("DEBUG: AppConstants access error: $e");
  }

  // Initialize SharedPreferences
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    debugPrint("DEBUG: SharedPreferences success");
  } catch (e) {
    debugPrint("DEBUG: SharedPreferences error: $e");
  }

  // Initialize Supabase
  try {
    if (AppConstants.supabaseUrl.isNotEmpty && AppConstants.supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      );
      debugPrint("DEBUG: Supabase initialized");
    } else {
      debugPrint("DEBUG: Supabase initialization skipped due to missing config");
    }
  } catch (e) {
    debugPrint("DEBUG: Supabase error: $e");
  }

  // Initialize AI
  try {
    AIService().init();
  } catch (e) {
    debugPrint("DEBUG: AI init error: $e");
  }

  // Initialize Push Notification Service (Firebase)
  try {
    await PushNotificationService().initialize();
  } catch (e) {
    debugPrint("DEBUG: Push notification init error: $e");
  }

  runApp(
    ProviderScope(
      overrides: [
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const GraceNoteApp(),
    ),
  );
}

// Global update notifier for PWA version detection
final UpdateNotifier _updateNotifier = kIsWeb ? UpdateNotifier() : UpdateNotifier();

class GraceNoteApp extends StatefulWidget {
  const GraceNoteApp({super.key});

  @override
  State<GraceNoteApp> createState() => _GraceNoteAppState();
}

class _GraceNoteAppState extends State<GraceNoteApp> {
  late final AuthChangeNotifier _authNotifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authNotifier = AuthChangeNotifier();
    _router = createAppRouter(_authNotifier);

    // Listen for password recovery events → navigate to password reset
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _router.push('/password-reset');
      }
    });

    // Set navigator key for push notification deep links
    PushNotificationService.navigatorKey = _router.routerDelegate.navigatorKey;
  }

  @override
  void dispose() {
    _authNotifier.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      theme: AppTheme.graceNoteTheme,
      appBuilder: (context) => MaterialApp.router(
        routerConfig: _router,
        title: AppConstants.appName,
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ko', 'KR'),
        ],
        builder: (context, child) => ShadAppBuilder(
          child: Stack(
            textDirection: ui.TextDirection.ltr,
            children: [
              child ?? Container(color: Colors.white, child: const Center(child: CircularProgressIndicator())),
              
              // DEV MODE INDICATOR
              if (AppConstants.supabaseUrl.contains('eftdf') || AppConstants.supabaseUrl.contains('127.0.0.1')) 
                Positioned(
                  top: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xCCEF4444),
                        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(8)),
                      ),
                      child: const Text(
                        'DEV MODE',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                      ),
                    ),
                  ),
                ),
              // UPDATE BANNER
              if (kIsWeb)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ListenableBuilder(
                    listenable: _updateNotifier,
                    builder: (context, _) {
                      if (!_updateNotifier.updateAvailable) return const SizedBox.shrink();
                      return Material(
                        color: Colors.transparent,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)]),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.system_update_rounded, color: Colors.white, size: 22),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('새로운 버전이 있습니다',
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                              ),
                              GestureDetector(
                                onTap: () => _updateNotifier.applyUpdate(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                  child: const Text('업데이트',
                                    style: TextStyle(color: Color(0xFF7C3AED), fontSize: 13, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
