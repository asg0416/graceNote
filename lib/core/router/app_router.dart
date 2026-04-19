import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Screens — Tabs
import 'package:grace_note/features/attendance/presentation/screens/attendance_prayer_screen.dart';
import 'package:grace_note/features/prayer/presentation/screens/prayer_list_screen.dart';
import 'package:grace_note/features/attendance/presentation/screens/attendance_dashboard_screen.dart';
import 'package:grace_note/features/attendance/presentation/screens/department_attendance_dashboard_screen.dart';
import 'package:grace_note/features/home/presentation/screens/more_screen.dart';
import 'package:grace_note/features/home/presentation/screens/member_my_prayer_screen.dart';
import 'package:grace_note/features/admin/presentation/screens/department_member_directory_screen.dart';

// Screens — Sub-routes (More)
import 'package:grace_note/features/home/presentation/screens/saved_prayers_screen.dart';
import 'package:grace_note/features/group_management/presentation/screens/group_leader_admin_screen.dart';
import 'package:grace_note/features/home/presentation/screens/ai_settings_screen.dart';
import 'package:grace_note/features/home/presentation/screens/profile_screen.dart';
import 'package:grace_note/features/settings/presentation/screens/notification_settings_screen.dart';
import 'package:grace_note/features/home/presentation/screens/notice_list_screen.dart';
import 'package:grace_note/features/home/presentation/screens/inquiry_screen.dart';
import 'package:grace_note/features/home/presentation/screens/service_guide_screen.dart';
import 'package:grace_note/features/settings/presentation/screens/change_password_screen.dart';

// Screens — Sub-routes (Group Management)
import 'package:grace_note/features/group_management/presentation/screens/member_edit_screen.dart';
import 'package:grace_note/features/admin/presentation/screens/admin_member_detail_screen.dart';

// Screens — Sub-routes (Prayer)
import 'package:grace_note/features/search/presentation/screens/search_screen.dart';

// Screens — Sub-routes (Attendance)
import 'package:grace_note/features/attendance/presentation/screens/attendance_check_screen.dart';
import 'package:grace_note/features/attendance/presentation/screens/prayer_share_screen.dart';

// Screens — Auth
import 'package:grace_note/features/auth/presentation/screens/login_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/password_reset_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/phone_verification_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/admin_pending_screen.dart';

// Core
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/services/push_notification_service.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:grace_note/core/widgets/push_permission_banner.dart';
import 'package:grace_note/core/widgets/iam_overlay.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:intl/intl.dart';


/// ChangeNotifier that listens to Supabase auth state changes.
/// Used as GoRouter's refreshListenable to trigger redirect on auth changes.
class AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  AuthChangeNotifier() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}


/// Navigator keys for each tab branch
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _recordTabKey = GlobalKey<NavigatorState>(debugLabel: 'record');
final _prayerTabKey = GlobalKey<NavigatorState>(debugLabel: 'prayer');
final _attendanceTabKey = GlobalKey<NavigatorState>(debugLabel: 'attendance');
final _moreTabKey = GlobalKey<NavigatorState>(debugLabel: 'more');

/// Creates the ROOT GoRouter instance.
/// This is now the SINGLE router for the entire app (no nesting).
GoRouter createAppRouter(AuthChangeNotifier authNotifier) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/record',
    debugLogDiagnostics: true,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      final location = state.matchedLocation;

      // Auth routes that don't require login
      final isAuthRoute = location == '/login' || 
                          location == '/password-reset';

      // Not logged in → redirect to login (unless already there)
      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }

      // Logged in but on login page → redirect to home
      if (isLoggedIn && location == '/login') {
        return '/record';
      }

      return null; // No redirect
    },
    routes: [
      // ── Auth Routes (outside shell) ──
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/password-reset',
        builder: (context, state) => const PasswordResetScreen(),
      ),

      // ── Authenticated Routes (with auth shell + tab shell) ──
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return ScaffoldWithNavBar(navigationShell: navigationShell);
            },
            branches: [
              // Tab 0: 기록 / 구성원 / 나의 기도
              StatefulShellBranch(
                navigatorKey: _recordTabKey,
                routes: [
                  GoRoute(
                    path: '/record',
                    pageBuilder: (context, state) => const NoTransitionPage(
                      child: _RecordTabPlaceholder(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'member-detail',
                        builder: (context, state) {
                          final extra = state.extra as Map<String, dynamic>;
                          return AdminMemberDetailScreen(
                            directoryMemberId: extra['directoryMemberId'] as String,
                            fullName: extra['fullName'] as String,
                            groupName: extra['groupName'] as String,
                            groupId: extra['groupId'] as String,
                            departmentId: extra['departmentId'] as String,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              // Tab 1: 기도소식
              StatefulShellBranch(
                navigatorKey: _prayerTabKey,
                routes: [
                  GoRoute(
                    path: '/prayer',
                    pageBuilder: (context, state) => const NoTransitionPage(
                      child: PrayerListScreen(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'search',
                        builder: (context, state) => const SearchScreen(),
                      ),
                    ],
                  ),
                ],
              ),

              // Tab 2: 출석 (leader/admin only — hidden for member)
              StatefulShellBranch(
                navigatorKey: _attendanceTabKey,
                routes: [
                  GoRoute(
                    path: '/attendance',
                    pageBuilder: (context, state) => const NoTransitionPage(
                      child: _AttendanceTabPlaceholder(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'check',
                        builder: (context, state) {
                          final extra = state.extra as Map<String, dynamic>;
                          return AttendanceCheckScreen(
                            initialMembers: extra['initialMembers'] as List<Map<String, dynamic>>,
                            isPastWeek: extra['isPastWeek'] as bool? ?? false,
                            groupId: extra['groupId'] as String?,
                            isNewFamilyGroup: extra['isNewFamilyGroup'] as bool? ?? false,
                          );
                        },
                      ),
                      GoRoute(
                        path: 'share',
                        builder: (context, state) {
                          final extra = state.extra as Map<String, dynamic>;
                          return PrayerShareScreen(
                            shareText: extra['shareText'] as String,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              // Tab 3 (or 2 for member): 더보기
              StatefulShellBranch(
                navigatorKey: _moreTabKey,
                routes: [
                  GoRoute(
                    path: '/more',
                    pageBuilder: (context, state) => const NoTransitionPage(
                      child: MoreScreen(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'saved-prayers',
                        builder: (context, state) => const SavedPrayersScreen(),
                      ),
                      GoRoute(
                        path: 'group-admin',
                        builder: (context, state) {
                          final extra = state.extra as Map<String, dynamic>;
                          return GroupLeaderAdminScreen(
                            groupId: extra['groupId'] as String,
                            groupName: extra['groupName'] as String,
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'member-edit',
                            builder: (context, state) {
                              final extra = state.extra as Map<String, dynamic>;
                              return MemberEditScreen(
                                groupId: extra['groupId'] as String,
                                groupName: extra['groupName'] as String,
                                member: extra['member'],
                              );
                            },
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'ai-settings',
                        builder: (context, state) => const AISettingsScreen(),
                      ),
                      GoRoute(
                        path: 'profile',
                        builder: (context, state) => const ProfileScreen(),
                      ),
                      GoRoute(
                        path: 'notifications',
                        builder: (context, state) => const NotificationSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'notices',
                        builder: (context, state) => const NoticeListScreen(),
                      ),
                      GoRoute(
                        path: 'inquiry',
                        builder: (context, state) => const InquiryScreen(),
                      ),
                      GoRoute(
                        path: 'guide',
                        builder: (context, state) => const ServiceGuideScreen(),
                      ),
                      GoRoute(
                        path: 'password',
                        builder: (context, state) => const ChangePasswordScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}


// ═══════════════════════════════════════════════════════════════════
// AuthenticatedShell — replaces AuthGate's post-auth logic
// Handles: profile loading, onboarding check, admin pending,
//          lifecycle data refresh, push notification init
// ═══════════════════════════════════════════════════════════════════

class AuthenticatedShell extends ConsumerStatefulWidget {
  final Widget child;
  const AuthenticatedShell({super.key, required this.child});

  @override
  ConsumerState<AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends ConsumerState<AuthenticatedShell> with WidgetsBindingObserver {
  bool _pushRequested = false;
  DateTime? _lastTokenRefresh; // 마지막 토큰 갱신 시각 추적

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed: Silently refreshing session and data');
      _refreshAllDataSilently();
      // 마지막 토큰 갱신으로부터 24시간 경과 시 재갱신 (Service Worker 업데이트 대응)
      if (kIsWeb && _pushRequested) {
        final now = DateTime.now();
        final shouldRefresh = _lastTokenRefresh == null ||
            now.difference(_lastTokenRefresh!).inHours >= 24;
        if (shouldRefresh) {
          _lastTokenRefresh = now;
          PushNotificationService().requestPermissionAndSaveToken();
          debugPrint('App resumed: FCM token refreshed (24h interval)');
        }
      }
    }
  }

  Future<void> _refreshAllDataSilently() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null || session.isExpired) {
        try { await Supabase.instance.client.auth.getUser(); } catch (_) {}
      }

      // 사용자가 텍스트 입력 중이면 data invalidation 건너뜀 (입력 유실 방지)
      final isEditing = ref.read(isUserEditingProvider);
      if (isEditing) {
        debugPrint('Silent refresh: User is editing, skipping data invalidation');
        return;
      }

      // [FIX] 백그라운드 복귀 시 전면적인 데이터 재생성 금지 (화면 파괴 방어)
      // StreamProvider가 자동으로 최신 상태를 유지하므로 invalidate 불필요
      // ref.invalidate(userProfileProvider);
      // ref.invalidate(userGroupsProvider);
    } catch (e) {
      debugPrint('Silent refresh failed: $e');
    }
  }

  void _refreshAllData() {
    ref.invalidate(authStateProvider);
    ref.invalidate(userProfileProvider);
    ref.invalidate(userProfileFutureProvider);
    ref.invalidate(userGroupsProvider);
    ref.invalidate(weekIdProvider);
  }

  void _requestPushPermission() {
    if (_pushRequested) return;
    _pushRequested = true;
    _lastTokenRefresh = DateTime.now();
    Future.delayed(const Duration(seconds: 2), () {
      PushNotificationService().requestPermissionAndSaveToken();
    });
    if (kIsWeb) {
      Future.delayed(const Duration(seconds: 1), () {
        PushNotificationService().checkInitialDeepLink();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT: Watch authStateProvider to keep the auth stream active.
    // userProfileProvider and userGroupsProvider depend on it internally.
    // Without this, the first auth event may not fire on page load,
    // leaving all downstream providers stuck in loading state.
    final authStateAsync = ref.watch(authStateProvider);
    
    // If auth state itself is still loading, show loading screen
    if (authStateAsync.isLoading && !authStateAsync.hasValue) {
      return _buildLoadingScreen('인증 상태 확인 중...');
    }

    final profileAsync = ref.watch(userProfileProvider);

    // Resilience: if we already have profile data, keep showing the app
    if (profileAsync.hasValue) {
      final profile = profileAsync.value;

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

      _requestPushPermission();
      return IamOverlay(child: widget.child); // Show the actual tab content
    }

    if (profileAsync.isLoading) {
      return _buildLoadingScreen('사용자 프로필 불러오는 중...');
    }

    // Transient error handling
    final errorStr = profileAsync.error.toString();
    final isTransientError = errorStr.contains('Realtime') || 
                            errorStr.contains('1006') || 
                            errorStr.contains('Failed to fetch');
    
    if (isTransientError) {
      return _buildLoadingScreen('연결을 복구하고 있습니다...');
    }

    return _buildErrorScreen(profileAsync.error ?? 'Unknown error');
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
            Text(message, style: const TextStyle(color: AppTheme.textSub, fontSize: 14, fontFamily: 'Pretendard')),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(Object error) {
    return _AutoRetryErrorScreen(
      error: error,
      onRetry: _refreshAllData,
      onLogout: () async {
        await Supabase.instance.client.auth.signOut();
        ref.invalidate(userProfileProvider);
        ref.invalidate(userGroupsProvider);
      },
    );
  }
}


// ═══════════════════════════════════════════════════════════════════
// ScaffoldWithNavBar — Bottom navigation bar management
// ═══════════════════════════════════════════════════════════════════

class ScaffoldWithNavBar extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  ConsumerState<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<ScaffoldWithNavBar> {
  bool _adminInitialNavDone = false;

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final activeRole = ref.watch(activeRoleProvider);
    final groupsAsync = ref.watch(userGroupsProvider);
    final unreadInquiries = ref.watch(unreadInquiryCountProvider).value ?? 0;
    final hasNewNotices = ref.watch(hasNewNoticesProvider).value ?? false;
    final hasBadge = unreadInquiries > 0 || hasNewNotices;

    // Role loading: if activeRole is null, check if data is still loading
    final profileAsync = ref.watch(userProfileProvider);
    if (activeRole == null) {
      // profile 또는 groups가 아직 로딩 중이면 로딩 화면 표시
      final isStillLoading = (groupsAsync.isLoading && !groupsAsync.hasValue) ||
                             (profileAsync.isLoading && !profileAsync.hasValue) ||
                             (!profileAsync.hasValue);
      if (isStillLoading) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShadcnSpinner(size: 32),
                const SizedBox(height: 24),
                const Text('그레이스노트를 준비하고 있습니다',
                  style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.5, fontFamily: 'Pretendard')),
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
              const Text('소속 정보를 불러올 수 없습니다', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('관리자가 아직 조를 배정하지 않았거나\n데이터 동기화 중일 수 있습니다.',
                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(userGroupsProvider);
                  ref.invalidate(userProfileProvider);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryViolet, foregroundColor: Colors.white,
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

    // admin 최초 진입 시 기도소식 탭(index 1)으로 이동
    if (activeRole == AppRole.admin && !_adminInitialNavDone) {
      _adminInitialNavDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && navigationShell.currentIndex != 1) {
          navigationShell.goBranch(1, initialLocation: true);
        }
      });
    }

    // Determine which branches are visible based on role
    final isMember = activeRole == AppRole.member;

    int currentVisualIndex;
    if (isMember) {
      switch (navigationShell.currentIndex) {
        case 0: currentVisualIndex = 0; break;
        case 1: currentVisualIndex = 1; break;
        case 3: currentVisualIndex = 2; break;
        default: currentVisualIndex = 0;
      }
    } else {
      currentVisualIndex = navigationShell.currentIndex;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const PushPermissionBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _buildNavItems(
              context: context,
              activeRole: activeRole,
              currentIndex: currentVisualIndex,
              hasBadge: hasBadge,
              onTap: (visualIndex) {
                int branchIndex;
                if (isMember) {
                  switch (visualIndex) {
                    case 0: branchIndex = 0; break;
                    case 1: branchIndex = 1; break;
                    case 2: branchIndex = 3; break;
                    default: branchIndex = 0;
                  }
                } else {
                  branchIndex = visualIndex;
                }
                navigationShell.goBranch(
                  branchIndex,
                  initialLocation: branchIndex == navigationShell.currentIndex,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNavItems({
    required BuildContext context,
    required AppRole? activeRole,
    required int currentIndex,
    required bool hasBadge,
    required void Function(int) onTap,
  }) {
    if (activeRole == AppRole.admin || activeRole == AppRole.leader) {
      return [
        _buildNavItem(index: 0, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.userCircle,
          label: activeRole == AppRole.admin ? '구성원' : '기록', onTap: onTap),
        _buildNavItem(index: 1, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.scrollText, label: '기도소식', onTap: onTap),
        _buildNavItem(index: 2, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.barChart3, label: '출석', onTap: onTap),
        _buildNavItem(index: 3, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.moreHorizontal, label: '더보기', hasBadge: hasBadge, onTap: onTap),
      ];
    } else {
      return [
        _buildNavItem(index: 0, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.userCircle, label: '나의 기도', onTap: onTap),
        _buildNavItem(index: 1, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.scrollText, label: '기도소식', onTap: onTap),
        _buildNavItem(index: 2, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.moreHorizontal, label: '더보기', hasBadge: hasBadge, onTap: onTap),
      ];
    }
  }

  Widget _buildNavItem({
    required int index, required int currentIndex,
    required IconData lucideIcon, required String label,
    required void Function(int) onTap, bool hasBadge = false,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppTheme.primaryViolet : const Color(0xFF94A3B8);

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(lucideIcon, size: 20, color: color),
                if (hasBadge)
                  Positioned(right: -2, top: -2,
                    child: Container(width: 5, height: 5,
                      decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle))),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: color, fontFamily: 'Pretendard', letterSpacing: -0.3)),
          ],
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════
// Tab Placeholder Widgets
// ═══════════════════════════════════════════════════════════════════

class _RecordTabPlaceholder extends ConsumerWidget {
  const _RecordTabPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRole = ref.watch(activeRoleProvider);
    final groupsAsync = ref.watch(userGroupsProvider);

    return groupsAsync.when(
      skipLoadingOnReload: true,
      skipError: true, // [FIX] 일시적 네트워크 에러 시 전체 화면 파괴(에러 스크린 전환) 방지
      data: (groups) {
        switch (activeRole) {
          case AppRole.admin:
            final profile = ref.watch(userProfileProvider).value;
            final adminGroup = groups.isNotEmpty ? groups.first : <String, dynamic>{};
            return DepartmentMemberDirectoryScreen(
              departmentId: profile?.departmentId ?? '',
              departmentName: '',
              profileMode: adminGroup['profile_mode'] ?? 'individual',
            );
          case AppRole.leader:
            if (groups.isEmpty) {
              return const Scaffold(body: Center(child: Text('기록할 조가 없습니다.')));
            }
            return const AttendancePrayerScreen(isActive: true);
          case AppRole.member:
            return const MemberMyPrayerScreen();
          default:
            return const Scaffold(body: Center(child: Text('역할을 선택해주세요.')));
        }
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('오류: $e'))),
    );
  }
}


class _AttendanceTabPlaceholder extends ConsumerWidget {
  const _AttendanceTabPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRole = ref.watch(activeRoleProvider);
    final groupsAsync = ref.watch(userGroupsProvider);
    final activeMembership = ref.watch(activeMembershipProvider);

    return groupsAsync.when(
      skipLoadingOnReload: true,
      skipError: true, // [FIX] 일시적 네트워크 에러 시 전체 화면 파괴 방지
      data: (groups) {
        // [FIX] admin은 group_members에 없을 수 있으므로 groups 체크보다 먼저 분기
        if (activeRole == AppRole.admin) {
          final profile = ref.watch(userProfileProvider).value;
          final adminGroup = groups.isNotEmpty ? groups.first : <String, dynamic>{};
          return DepartmentAttendanceDashboardScreen(
            departmentId: profile?.departmentId ?? '',
            departmentName: '',
            isCoupleMode: adminGroup['profile_mode'] == 'couple',
          );
        }

        if (groups.isEmpty) {
          return const Scaffold(body: Center(child: Text('출석 데이터가 없습니다.')));
        }

        // leader
        final targetGroupId = activeMembership?.groupId ?? 
            (groups.isNotEmpty ? groups.first['group_id'] : '');
        final targetGroupName = activeMembership?.groupName ?? 
            (groups.isNotEmpty ? groups.first['group_name'] : '');
        return AttendanceDashboardScreen(
          groupId: targetGroupId,
          groupName: targetGroupName,
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('오류: $e'))),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════
// Auto-Retry Error Screen (moved from main.dart)
// ═══════════════════════════════════════════════════════════════════

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
        setState(() {});
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
              const Icon(Icons.wifi_off_rounded, size: 64, color: Color(0xFFEF4444)),
              const SizedBox(height: 16),
              Text(displayMessage, textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMain, fontSize: 16, fontWeight: FontWeight.w600, height: 1.5)),
              if (_lastRetryTime != null)
                Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text('마지막 재시도: ${DateFormat('HH:mm:ss').format(_lastRetryTime!)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSub))),
              if (!isRealtimeError)
                Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(errorMessage, style: const TextStyle(fontSize: 12, color: AppTheme.textSub),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity,
                child: ElevatedButton(onPressed: widget.onRetry,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryViolet, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                  child: const Text('다시 시도', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)))),
              const SizedBox(height: 12),
              TextButton(onPressed: widget.onLogout,
                child: const Text('로그아웃 및 계정 전환', style: TextStyle(color: AppTheme.textSub))),
            ],
          ),
        ),
      ),
    );
  }
}
