import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/features/attendance/presentation/screens/attendance_prayer_screen.dart';
import 'package:grace_note/features/home/presentation/screens/more_screen.dart';
import 'package:grace_note/features/home/presentation/screens/member_my_prayer_screen.dart';
import 'package:grace_note/features/prayer/presentation/screens/prayer_list_screen.dart';
import 'package:grace_note/features/admin/presentation/screens/department_member_directory_screen.dart';
import 'package:grace_note/features/attendance/presentation/screens/attendance_dashboard_screen.dart';
import 'package:grace_note/features/home/presentation/screens/inquiry_screen.dart';
import 'package:grace_note/core/widgets/droplet_loader.dart';
import 'package:grace_note/features/attendance/presentation/screens/department_attendance_dashboard_screen.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // 역할 전환 시 인덱스 리셋
    ref.listen<AppRole?>(activeRoleProvider, (previous, next) {
      if (previous != next) {
        if (mounted) {
          setState(() => _selectedIndex = 0);
        }
      }
    });

    final profile = ref.watch(userProfileProvider).value;
    final groupsAsync = ref.watch(userGroupsProvider);
    final activeRole = ref.watch(activeRoleProvider);
    
    // Fetch department name if profile has departmentId
    final departmentNameAsync = profile?.departmentId != null
        ? ref.watch(departmentNameProvider(profile!.departmentId!))
        : const AsyncValue<String>.data('내 부서');

    return groupsAsync.when(
      data: (groups) {
        if (activeRole == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final List<Widget> screens;
        
        switch (activeRole) {
          case AppRole.admin:
            screens = [
              profile?.departmentId != null && profile!.departmentId!.isNotEmpty
                ? DepartmentMemberDirectoryScreen(
                    departmentId: profile.departmentId!,
                    departmentName: departmentNameAsync.value ?? '내 부서',
                  )
                : const Scaffold(body: Center(child: Text('부서 정보가 없습니다.'))),
              const PrayerListScreen(),
              profile?.departmentId != null && profile!.departmentId!.isNotEmpty
                ? DepartmentAttendanceDashboardScreen(
                    departmentId: profile.departmentId!,
                    departmentName: departmentNameAsync.value ?? '내 부서',
                  )
                : const Scaffold(body: Center(child: Text('출석 데이터가 없습니다.'))),
              const MoreScreen(),
            ];
            break;
          case AppRole.leader:
            screens = [
              groups.isNotEmpty
                ? AttendancePrayerScreen(isActive: _selectedIndex == 0)
                : const Scaffold(body: Center(child: Text('기록할 조가 없습니다.'))),
              const PrayerListScreen(),
              groups.isNotEmpty 
                ? AttendanceDashboardScreen(groupId: groups.first['group_id'], groupName: groups.first['group_name'])
                : const Scaffold(body: Center(child: Text('출석 데이터가 없습니다.'))),
              const MoreScreen(),
            ];
            break;
          case AppRole.member:
            screens = [
              const MemberMyPrayerScreen(),
              const PrayerListScreen(),
              const MoreScreen(),
            ];
            break;
        }

        return Scaffold(
          body: IndexedStack(
            index: _selectedIndex >= screens.length ? 0 : _selectedIndex,
            children: screens,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex >= screens.length ? 0 : _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppTheme.primaryIndigo,
            unselectedItemColor: AppTheme.textLight,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            items: _buildBottomNavBarItems(ref, activeRole),
          ),
        );
      },
      loading: () => const Scaffold(
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
      ),
      error: (e, s) => Scaffold(body: Center(child: Text('데이터 로드 오류: $e'))),
    );
  }

  List<BottomNavigationBarItem> _buildBottomNavBarItems(WidgetRef ref, AppRole role) {
    final unreadInquiries = ref.watch(unreadInquiryCountProvider).value ?? 0;
    final hasNewNotices = ref.watch(hasNewNoticesProvider).value ?? false;

    Widget buildIconWithBadge(IconData icon, bool hasBadge) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon),
          if (hasBadge)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      );
    }

    if (role == AppRole.admin || role == AppRole.leader) {
      return [
        BottomNavigationBarItem(
          icon: const Icon(Icons.people_alt_rounded), 
          label: role == AppRole.admin ? '구성원' : '기록',
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_motion_rounded), label: '기도소식'),
        const BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: '출석'),
        BottomNavigationBarItem(
          icon: buildIconWithBadge(
            Icons.more_horiz_rounded,
            (unreadInquiries > 0 || hasNewNotices), // Any notification
          ),
          label: '더보기',
        ),
      ];
    } else {
      return [
        const BottomNavigationBarItem(icon: Icon(Icons.history_edu_rounded), label: '나의 기도'),
        const BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_motion_rounded), label: '기도소식'),
        BottomNavigationBarItem(
          icon: buildIconWithBadge(
            Icons.more_horiz_rounded,
            (unreadInquiries > 0 || hasNewNotices), // Any notification
          ),
          label: '더보기',
        ),
      ];
    }
  }
}
