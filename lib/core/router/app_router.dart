import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

// Core
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

/// Navigator keys for each tab branch
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _recordTabKey = GlobalKey<NavigatorState>(debugLabel: 'record');
final _prayerTabKey = GlobalKey<NavigatorState>(debugLabel: 'prayer');
final _attendanceTabKey = GlobalKey<NavigatorState>(debugLabel: 'attendance');
final _moreTabKey = GlobalKey<NavigatorState>(debugLabel: 'more');

/// Creates the GoRouter instance for the authenticated home screen.
/// This router is used INSIDE HomeScreen (post-auth), not globally.
GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/record',
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
  );
}


/// Scaffold wrapper that provides the BottomNavigationBar
class ScaffoldWithNavBar extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRole = ref.watch(activeRoleProvider);
    final unreadInquiries = ref.watch(unreadInquiryCountProvider).value ?? 0;
    final hasNewNotices = ref.watch(hasNewNoticesProvider).value ?? false;
    final hasBadge = unreadInquiries > 0 || hasNewNotices;

    // Determine which branches are visible based on role
    // admin/leader: 4 tabs (record, prayer, attendance, more)
    // member: 3 tabs (record, prayer, more) — attendance hidden
    final isMember = activeRole == AppRole.member;

    // Map visual tab index to branch index
    int currentVisualIndex;
    if (isMember) {
      // member: branch 0=기록, 1=기도소식, 3=더보기
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
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFF1F5F9), width: 1),
          ),
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
                  // Map visual index back to branch index
                  switch (visualIndex) {
                    case 0: branchIndex = 0; break; // 나의 기도
                    case 1: branchIndex = 1; break; // 기도소식
                    case 2: branchIndex = 3; break; // 더보기
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
        _buildNavItem(
          index: 0, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.userCircle,
          label: activeRole == AppRole.admin ? '구성원' : '기록',
          onTap: onTap,
        ),
        _buildNavItem(
          index: 1, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.scrollText,
          label: '기도소식',
          onTap: onTap,
        ),
        _buildNavItem(
          index: 2, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.barChart3,
          label: '출석',
          onTap: onTap,
        ),
        _buildNavItem(
          index: 3, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.moreHorizontal,
          label: '더보기',
          hasBadge: hasBadge,
          onTap: onTap,
        ),
      ];
    } else {
      return [
        _buildNavItem(
          index: 0, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.userCircle,
          label: '나의 기도',
          onTap: onTap,
        ),
        _buildNavItem(
          index: 1, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.scrollText,
          label: '기도소식',
          onTap: onTap,
        ),
        _buildNavItem(
          index: 2, currentIndex: currentIndex,
          lucideIcon: lucide.LucideIcons.moreHorizontal,
          label: '더보기',
          hasBadge: hasBadge,
          onTap: onTap,
        ),
      ];
    }
  }

  Widget _buildNavItem({
    required int index,
    required int currentIndex,
    required IconData lucideIcon,
    required String label,
    required void Function(int) onTap,
    bool hasBadge = false,
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
                  Positioned(
                    right: -2, top: -2,
                    child: Container(
                      width: 5, height: 5,
                      decoration: const BoxDecoration(
                        color: AppTheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: color,
                fontFamily: 'Pretendard',
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Placeholder widget for the record tab — renders different screens based on role
class _RecordTabPlaceholder extends ConsumerWidget {
  const _RecordTabPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRole = ref.watch(activeRoleProvider);
    final groupsAsync = ref.watch(userGroupsProvider);

    return groupsAsync.when(
      data: (groups) {
        switch (activeRole) {
          case AppRole.admin:
            final profile = ref.watch(userProfileProvider).value;
            return DepartmentMemberDirectoryScreen(
              departmentId: profile?.departmentId ?? '',
              departmentName: '',
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


/// Placeholder widget for the attendance tab — renders different screens based on role
class _AttendanceTabPlaceholder extends ConsumerWidget {
  const _AttendanceTabPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRole = ref.watch(activeRoleProvider);
    final groupsAsync = ref.watch(userGroupsProvider);
    final activeMembership = ref.watch(activeMembershipProvider);

    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const Scaffold(body: Center(child: Text('출석 데이터가 없습니다.')));
        }

        if (activeRole == AppRole.admin) {
          final profile = ref.watch(userProfileProvider).value;
          return DepartmentAttendanceDashboardScreen(
            departmentId: profile?.departmentId ?? '',
            departmentName: '',
          );
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
