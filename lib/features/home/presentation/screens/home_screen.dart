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
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:grace_note/features/attendance/presentation/screens/department_attendance_dashboard_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:grace_note/core/widgets/shad_layout.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';
import 'package:grace_note/features/search/presentation/screens/search_screen.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:animations/animations.dart' as animations;
import 'package:supabase_flutter/supabase_flutter.dart';

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
                    ),
                    child: const Text('다시 시도'),
                  ),
                  TextButton(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    child: const Text('로그아웃 및 다시 로그인', style: TextStyle(color: AppTheme.textSub)),
                  ),
                ],
              ),
            ),
          );
        }

        final List<Widget> screens;
        String title = '';
        
        switch (activeRole) {
          case AppRole.admin:
            title = departmentNameAsync.value ?? '구성원';
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
            title = _selectedIndex == 0 
                ? (groups.isNotEmpty ? '${groups.first['group_name']} 기록' : '기록')
                : (_selectedIndex == 1 ? '기도소식' : (_selectedIndex == 2 ? '출석 통계' : '더보기'));
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
            title = _selectedIndex == 0 ? '나의 기도' : (_selectedIndex == 1 ? '기도소식' : '더보기');
            screens = [
              const MemberMyPrayerScreen(),
              const PrayerListScreen(),
              const MoreScreen(),
            ];
            break;
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: IndexedStack(
            index: _selectedIndex >= screens.length ? 0 : _selectedIndex,
            children: screens,
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Color(0xFFF1F5F9), width: 1), // v0 정밀 보더
              ),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
            child: SizedBox(
              height: 60, // v0 높이 축소
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _buildBottomNavBarItems(ref, activeRole),
              ),
            ),
          ),
        );
      },
      loading: () => Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadcnSpinner(size: 32), // v0 축소
              const SizedBox(height: 24),
              const Text(
                '그레이스노트를 준비하고 있습니다',
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 15, // v0 축소
                  letterSpacing: -0.5,
                  fontFamily: 'Pretendard',
                ),
              ),
            ],
          ),
        ),
      ),
      error: (e, s) => Scaffold(body: Center(child: Text('데이터 로드 오류: $e'))),
    );
  }

  List<Widget> _buildBottomNavBarItems(WidgetRef ref, AppRole role) {
    final unreadInquiries = ref.watch(unreadInquiryCountProvider).value ?? 0;
    final hasNewNotices = ref.watch(hasNewNoticesProvider).value ?? false;

    if (role == AppRole.admin || role == AppRole.leader) {
      return [
        _buildNavItem(
          index: 0,
          lucideIcon: lucide.LucideIcons.userCircle, // v0 아이콘 변경
          label: role == AppRole.admin ? '구성원' : '기록',
        ),
        _buildNavItem(
          index: 1,
          lucideIcon: lucide.LucideIcons.scrollText, // v0 아이콘 변경
          label: '기도소식',
        ),
        _buildNavItem(
          index: 2,
          lucideIcon: lucide.LucideIcons.barChart3, // v0 아이콘 변경
          label: '출석',
        ),
        _buildNavItem(
          index: 3,
          lucideIcon: lucide.LucideIcons.moreHorizontal,
          label: '더보기',
          hasBadge: (unreadInquiries > 0 || hasNewNotices),
        ),
      ];
    } else {
      return [
        _buildNavItem(
          index: 0,
          lucideIcon: lucide.LucideIcons.userCircle,
          label: '나의 기도',
        ),
        _buildNavItem(
          index: 1,
          lucideIcon: lucide.LucideIcons.scrollText,
          label: '기도소식',
        ),
        _buildNavItem(
          index: 2,
          lucideIcon: lucide.LucideIcons.moreHorizontal,
          label: '더보기',
          hasBadge: (unreadInquiries > 0 || hasNewNotices),
        ),
      ];
    }
  }

  Widget _buildNavItem({
    required int index,
    required IconData lucideIcon,
    required String label,
    bool hasBadge = false,
  }) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? AppTheme.primaryViolet : const Color(0xFF94A3B8); // v0 미선택 컬러

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedIndex = index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  lucideIcon,
                  size: 20, // v0 정밀 축소
                  color: color,
                ),
                if (hasBadge)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 5,
                      height: 5,
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
                fontSize: 11, // v0 축소
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, // v0 Medium(500)/SemiBold(600)
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

  Future<void> _showDatePickerForPrayerList(BuildContext context, WidgetRef ref) async {
    final selectedDate = ref.read(selectedWeekDateProvider);
    final date = await showDatePicker(
      context: context, 
      initialDate: selectedDate, 
      firstDate: DateTime(2023), 
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: AppTheme.light.copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryViolet,
              onPrimary: Colors.white,
              onSurface: AppTheme.textMain,
            ),
          ),
          child: child!,
        );
      }
    );
    if (date != null) {
      ref.read(selectedWeekDateProvider.notifier).state = date;
    }
  }
}
