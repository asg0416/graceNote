import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/router/app_router.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter();
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 역할 전환 시 라우터를 초기 위치로 리셋
    ref.listen<AppRole?>(activeRoleProvider, (previous, next) {
      if (previous != next) {
        _router.go('/record');
      }
    });

    final groupsAsync = ref.watch(userGroupsProvider);
    final activeRole = ref.watch(activeRoleProvider);

    // [FIX] Resilience: 이미 데이터가 있는 경우, 로딩이나 에러 중이라도 기존 화면을 유지하여 깜빡임을 방지합니다.
    if (groupsAsync.hasValue) {
      if (activeRole == null) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(lucide.LucideIcons.alertCircle, size: 48, color: AppTheme.textSub),
                const SizedBox(height: 16),
                const Text(
                  '소속 정보를 불러올 수 없습니다',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '관리자가 아직 조를 배정하지 않았거나\n데이터 동기화 중일 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSub, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(userGroupsProvider);
                    ref.invalidate(userProfileProvider);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryViolet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('다시 시도', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      }

      // go_router의 Router widget 사용
      return Router.withConfig(config: _router);
    }

    if (groupsAsync.isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadcnSpinner(size: 32),
              const SizedBox(height: 24),
              const Text(
                '그레이스노트를 준비하고 있습니다',
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: -0.5,
                  fontFamily: 'Pretendard',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(lucide.LucideIcons.alertCircle, size: 48, color: AppTheme.textSub),
            const SizedBox(height: 16),
            Text('데이터 로드 오류: ${groupsAsync.error}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.invalidate(userGroupsProvider),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
