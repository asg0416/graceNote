import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/auth/presentation/screens/login_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/church_selection_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/phone_verification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/services/ai_service.dart';
import 'package:grace_note/features/home/presentation/screens/home_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/admin_pending_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:grace_note/core/widgets/droplet_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // Initialize Supabase
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Initialize AI
  AIService().init();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const GraceNoteApp(),
    ),
  );
}

class GraceNoteApp extends StatelessWidget {
  const GraceNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Watch Auth State Reactive (IMPORTANT: Rebuilds on login/signup)
    final authStateAsync = ref.watch(authStateProvider);

    // [ENHANCEMENT] Invalidate user profile and related data on auth change
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.value?.session?.user.id != next.value?.session?.user.id) {
        ref.invalidate(userProfileProvider);
        ref.invalidate(userGroupsProvider);
      }
    });

    return authStateAsync.when(
      data: (authState) {
        final session = authState.session;

        // Not logged in
        if (session == null) {
          return const LoginScreen();
        }

        // 2. Logged in - Load Profile and route
        final profileAsync = ref.watch(userProfileProvider);

        return profileAsync.when(
          data: (profile) {
            // 프로필이 아직 생성되지 않았거나 온보딩이 완료되지 않은 경우
            if (profile == null || !profile.isOnboardingComplete) {
              return const PhoneVerificationScreen();
            }

            // 2. 관리자 권한 신청 중이거나 승인 대기인 경우 (마스터 계정은 예외)
            final bool isPendingAdmin = profile.adminStatus == 'pending' || 
                                      (profile.role == 'admin' && profile.adminStatus != 'approved');
            
            if (isPendingAdmin && !profile.isMaster) {
              return const AdminPendingScreen();
            }

            // 3. Ready to go
            return const HomeScreen();
          },
          loading: () {
            // [ENHANCEMENT] Show a timeout-based Check button if loading takes too long
            return FutureBuilder(
              future: Future.delayed(const Duration(seconds: 5)),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return _buildSlowLoadingScreen(ref);
                }
                return _buildLoadingScreen();
              },
            );
          },
          error: (e, _) => _buildErrorScreen(context, ref, e),
        );
      },
      loading: () => _buildLoadingScreen(),
      error: (e, _) => _buildErrorScreen(context, ref, e),
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropletLoader(size: 80),
            SizedBox(height: 24),
            Text(
              '그레이스노트를 준비하고 있습니다',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: -0.5,
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
            const DropletLoader(size: 80),
            const SizedBox(height: 24),
            const Text(
              '데이터를 불러오는데 시간이 조금 걸리네요',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 16,
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

  Widget _buildErrorScreen(BuildContext context, WidgetRef ref, Object error) {
    // 에러 메시지 분석 (Realtime 관련 에러인 경우 사용자 친화적 메시지 제공)
    final errorMessage = error.toString();
    final isRealtimeError = errorMessage.contains('Realtime');
    final displayMessage = isRealtimeError 
        ? '서버와의 연결이 원활하지 않습니다.\n잠시 후 다시 시도해 주세요.' 
        : '로그인 정보를 불러오는 중 오류가 발생했습니다.';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRealtimeError ? Icons.wifi_off_rounded : Icons.error_outline_rounded, 
                size: 48, 
                color: AppTheme.error
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
                  onPressed: () {
                    // [RETRY LOGIC] 강력한 초기화 및 재시도
                    ref.invalidate(authStateProvider);
                    ref.invalidate(userProfileProvider);
                    ref.invalidate(userProfileFutureProvider);
                    ref.invalidate(userGroupsProvider);
                    ref.invalidate(weekIdProvider);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryIndigo,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('다시 시도', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  // 로그아웃 시에도 데이터 클리어
                  ref.invalidate(userProfileProvider);
                  ref.invalidate(userGroupsProvider);
                },
                child: const Text('로그아웃 및 계정 전환', style: TextStyle(color: AppTheme.textSub)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
