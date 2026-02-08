import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // [FIX] import 추가
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/auth/presentation/screens/login_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/phone_verification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/services/ai_service.dart';
import 'package:grace_note/features/home/presentation/screens/home_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/admin_pending_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/features/auth/presentation/screens/password_reset_screen.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  runApp(
    ProviderScope(
      overrides: [
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const GraceNoteApp(),
    ),
  );
}

class GraceNoteApp extends StatelessWidget {
  const GraceNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      theme: AppTheme.graceNoteTheme,
      appBuilder: (context) => MaterialApp(
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
                        color: Color(0xCCEF4444), // Red-500 with 80% opacity
                        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(8)),
                      ),
                      child: const Text(
                        'DEV MODE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const PasswordResetScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed: Skipping auto-refresh to maintain UI state');
      // [FIX] 포커스 돌아올 때마다 새로고침되는 문제 해결을 위해 자동 갱신 중단
      // _refreshAllData(); 
    }
  }

  void _refreshAllData() {
    ref.invalidate(authStateProvider);
    ref.invalidate(userProfileProvider);
    ref.invalidate(userProfileFutureProvider);
    ref.invalidate(userGroupsProvider);
    ref.invalidate(weekIdProvider);
  }

  @override
  Widget build(BuildContext context) {
    final authStateAsync = ref.watch(authStateProvider);

    // 1. Auth State Handling with Resilience
    // 이미 데이터가 있는 경우(hasValue) 에러나 로딩 중이라도 기존 화면을 최대한 유지합니다.
    if (authStateAsync.isLoading && !authStateAsync.hasValue) {
      return _buildLoadingScreen('인증 상태 확인 중...');
    }

    if (authStateAsync.hasError && !authStateAsync.hasValue) {
      return _AutoRetryErrorScreen(
        error: authStateAsync.error!,
        onRetry: _refreshAllData,
        onLogout: () async {
          await Supabase.instance.client.auth.signOut();
          ref.invalidate(userProfileProvider);
          ref.invalidate(userGroupsProvider);
        },
      );
    }

    final authState = authStateAsync.valueOrNull;
    final session = authState?.session;

    // Not logged in
    if (session == null) {
      return const LoginScreen();
    }

    // 2. Profile Handling with Resilience
    final profileAsync = ref.watch(userProfileProvider);

    // [FIX] Resilience: 이미 데이터가 있는 경우(hasValue), 로딩이나 에러 중이라도 기존 화면을 유지하여 깜빡임을 방지합니다.
    if (profileAsync.hasValue) {
      final profile = profileAsync.value;
      
      // [FIX] 프로필 생성/로딩 지연 시 깜빡임 방지: 프로필이 null이면 로딩 중으로 간주
      if (profile == null) {
        return _buildLoadingScreen('프로필 정보를 확인하고 있습니다...'); 
      }

      if (!profile.isOnboardingComplete) {
        return const PhoneVerificationScreen();
      }
      final bool isPendingAdmin = profile.adminStatus == 'pending' || 
                                  (profile.role == 'admin' && profile.adminStatus != 'approved');
      if (isPendingAdmin && !profile.isMaster) {
        return const AdminPendingScreen();
      }
      return const HomeScreen();
    }

    if (profileAsync.isLoading) {
      return _buildLoadingScreen('사용자 프로필 불러오는 중...');
    }

    // 데이터가 전혀 없고 에러인 경우(최초 진입 등)에만 에러 화면 노출
    return _AutoRetryErrorScreen(
      error: profileAsync.error ?? 'Unknown error',
      onRetry: _refreshAllData,
      onLogout: () async {
        await Supabase.instance.client.auth.signOut();
        ref.invalidate(userProfileProvider);
        ref.invalidate(userGroupsProvider);
      },
    );
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              message,
              style: const TextStyle(
                color: AppTheme.textSub,
                fontSize: 14,
                fontFamily: 'Pretendard',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlowLoadingScreen(WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            const Text(
              '데이터를 불러오는데 시간이 조금 걸리네요',
              style: TextStyle(
                color: AppTheme.textMain, 
                fontWeight: FontWeight.w800, 
                fontSize: 16
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                // [RETRY LOGIC] 모든 주요 데이터 초기화
                ref.invalidate(authStateProvider);
                ref.invalidate(userProfileProvider);
                ref.invalidate(userProfileFutureProvider);
                ref.invalidate(userGroupsProvider);
                ref.invalidate(weekIdProvider);
              },
              child: const Text('다시 시도'),
            ),
            TextButton(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              child: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoRetryErrorScreen extends StatefulWidget {
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  const _AutoRetryErrorScreen({
    required this.error,
    required this.onRetry,
    required this.onLogout,
  });

  @override
  State<_AutoRetryErrorScreen> createState() => _AutoRetryErrorScreenState();
}

class _AutoRetryErrorScreenState extends State<_AutoRetryErrorScreen> {
  DateTime? _lastRetryTime;

  @override
  void initState() {
    super.initState();
    _startAutoRetry();
  }

  void _startAutoRetry() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) {
        debugPrint('Auto-retrying connection...');
        _lastRetryTime = DateTime.now();
        widget.onRetry();
        setState(() {}); // Update last retry time display if needed
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = widget.error.toString();
    final isRealtimeError = errorMessage.contains('Realtime');
    final displayMessage = '서버와의 연결이 원활하지 않습니다.\n잠시 후 다시 시도해 주세요.';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.wifi_off_rounded, 
                size: 64, 
                color: Color(0xFFEF4444), // AppTheme.error
              ),
              const SizedBox(height: 16),
              Text(
                displayMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textMain, 
                  fontSize: 16, 
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              if (_lastRetryTime != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '마지막 재시도: ${DateFormat('HH:mm:ss').format(_lastRetryTime!)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSub),
                  ),
                ),
              if (!isRealtimeError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSub),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryViolet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('다시 시도', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: widget.onLogout,
                child: const Text('로그아웃 및 계정 전환', style: TextStyle(color: AppTheme.textSub)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
