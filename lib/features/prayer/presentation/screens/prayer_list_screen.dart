import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/search/presentation/screens/search_screen.dart';
import 'package:grace_note/features/prayer/presentation/widgets/prayer_card.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

import 'package:grace_note/core/providers/user_role_provider.dart';
import 'package:grace_note/core/utils/route_util.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

class PrayerListScreen extends ConsumerStatefulWidget {
  const PrayerListScreen({super.key});

  @override
  ConsumerState<PrayerListScreen> createState() => _PrayerListScreenState();
}

class _PrayerListScreenState extends ConsumerState<PrayerListScreen> with TickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, dynamic>> _allGroups = [{'id': 'all', 'name': '전체'}];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.invalidate(userGroupsProvider));
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    // [FIX] 데이터 정합성을 위해 연관된 모든 Provider 초기화
    // 1. 소속 정보 갱신
    ref.invalidate(userGroupsProvider);
    final groups = await ref.read(userGroupsProvider.future);
    
    // 2. 주차 ID 갱신 (소속이 변경되면 주차 계산 로직도 달라질 수 있음)
    final profile = ref.read(userProfileProvider).value;
    if (profile != null && profile.churchId != null) {
      ref.invalidate(weekIdProvider(profile.churchId!));
    }

    // 3. 실제 기도 데이터 갱신
    ref.invalidate(weeklyDataProvider);
    ref.invalidate(departmentWeeklyDataProvider);
  }

  Future<void> _selectDate(BuildContext context) async {
    final selectedDate = ref.read(selectedWeekDateProvider);
    final date = await showDatePicker(
      context: context, 
      initialDate: selectedDate, 
      firstDate: DateTime(2023), 
      lastDate: DateTime(2030)
    );
    if (date != null) {
      ref.read(selectedWeekDateProvider.notifier).state = date;
    }
  }

  void _moveWeek(int weeks) {
    final current = ref.read(selectedWeekDateProvider);
    ref.read(selectedWeekDateProvider.notifier).state = current.add(Duration(days: 7 * weeks));
  }

  Widget _buildWeekNavigator(DateTime date) {
    final int weekNumber = ((date.day - 1) / 7).floor() + 1;
    final String weekStr = '${date.month}월 ${weekNumber}주차';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8), // v0 축소
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _moveWeek(-1),
            icon: Icon(lucide.LucideIcons.chevronLeft, color: AppTheme.textSub, size: 18), // v0 축소
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 340,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('주차 선택 (일요일)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textMain, fontFamily: 'Pretendard')),
                          ),
                          const Divider(height: 24),
                          shad.ShadCalendar(
                            selected: date,
                            weekStartsOn: 7,
                            selectableDayPredicate: (date) => date.weekday == DateTime.sunday,
                            onChanged: (newDate) {
                              if (newDate != null) {
                                ref.read(selectedWeekDateProvider.notifier).state = newDate;
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC), // v1 연한 회색 배경
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)), // v1 회색 테두리
              ),
              child: Text(
                weekStr,
                style: const TextStyle(
                  fontSize: 15, // v1 폰트 크기
                  fontWeight: FontWeight.w600, // v1 폰트 굵기
                  color: Color(0xFF1E293B), // v1 폰트 색상
                  fontFamily: 'Pretendard',
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _moveWeek(1),
            icon: Icon(lucide.LucideIcons.chevronRight, color: AppTheme.textSub, size: 18), // v0 축소
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);
    final selectedDate = ref.watch(selectedWeekDateProvider);
    final activeRole = ref.watch(activeRoleProvider);
    
    final userGroupsAsync = ref.watch(userGroupsProvider);
    final userGroups = userGroupsAsync.value ?? [];

    String appBarTitle = '기도소식';
    // ... 기존 타이틀 결정 로직 동일 ...

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 52, // v0 명시적 높이
        leadingWidth: 56,
        leading: IconButton(
          onPressed: () => _refreshData(),
          icon: Icon(lucide.LucideIcons.refreshCw, color: AppTheme.primaryViolet, size: 18),
        ),
        title: Text(appBarTitle, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, SharedAxisPageRoute(page: const SearchScreen())),
            icon: Icon(lucide.LucideIcons.search, color: AppTheme.primaryViolet, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildWeekNavigator(selectedDate),
          // const Divider(height: 1), // v1 하단 선 제거 요청 반영
          Expanded(
            child: userProfileAsync.when(
              data: (profile) {
                if (profile == null) return const Center(child: Text('로그인이 필요합니다.'));
                if (activeRole == null) return const Center(child: CircularProgressIndicator());
                
                return ref.watch(userGroupsProvider).when(
                  data: (userGroups) {
                    final bool isLeaderOrAdmin = activeRole == AppRole.admin || activeRole == AppRole.leader;
                    
                    if (isLeaderOrAdmin) {
                      final deptId = profile.departmentId;
                      if (deptId == null || deptId.isEmpty) {
                        return const Center(child: Text('소속 부서 정보가 없습니다.'));
                      }

                      return ref.watch(departmentGroupsProvider(deptId)).when(
                        skipLoadingOnRefresh: true,
                        data: (deptGroups) {
                          if (deptGroups.isEmpty) return _buildTabLayout(profile, userGroups, activeRole);
                          return _buildTabLayout(profile, deptGroups, activeRole);
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, s) => Center(child: Text('부서 조 목록 로딩 실패: $e')),
                      );
                    } else {
                      final memberGroups = userGroups.where((g) => g['role_in_group'] == 'member').toList();
                      final groupsToUse = memberGroups.isNotEmpty ? memberGroups : userGroups;
                      
                      if (groupsToUse.isEmpty) return const Center(child: Text('소속된 조가 없습니다.'));
                      
                      final firstGroupId = (groupsToUse.first['id'] ?? groupsToUse.first['group_id']).toString();
                      return _buildPrayerListContainer(firstGroupId, profile.churchId ?? '', profile.departmentId ?? '');
                    }
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Center(child: Text('소속 정보 로딩 실패: $e')),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('프로필 로딩 실패: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabLayout(ProfileModel profile, List<Map<String, dynamic>> groups, AppRole activeRole) {
    final churchId = profile.churchId ?? '';
    final departmentId = profile.departmentId ?? '';
    final bool isLeaderOrAdmin = activeRole == AppRole.admin || activeRole == AppRole.leader;
    
    final List<Map<String, dynamic>> unifiedGroups = groups.map((g) => {
      'id': (g['id'] ?? g['group_id']).toString(),
      'name': (g['name'] ?? g['group_name'] ?? '').toString(),
      'role_in_group': g['role_in_group'],
    }).toList();

    if (isLeaderOrAdmin) {
      _allGroups = [{'id': 'all', 'name': '전체'}, ...unifiedGroups];
    } else {
      _allGroups = unifiedGroups;
    }
    
    final tabCount = _allGroups.length;

    if (_tabController == null || _tabController!.length != tabCount) {
      _tabController?.dispose();
      _tabController = TabController(length: tabCount, vsync: this);
    }

    return Column(
      children: [
        if (tabCount > 1) 
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8), 
            decoration: const BoxDecoration(
              color: Colors.white, 
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1), // v1 아래 선만 남김
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicator: BoxDecoration(
                color: const Color(0xFFF3F0FF), // v1 연보라 배경 (활성)
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              labelColor: const Color(0xFF7C3AED), // v1 짙은 보라 글씨 (활성)
              unselectedLabelColor: const Color(0xFF64748B), 
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'Pretendard'),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, fontFamily: 'Pretendard'),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              tabs: _allGroups.map((g) => Tab(
                height: 40, 
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text((g['name'] ?? '').toString()),
                ),
              )).toList(),
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _allGroups.map((g) => _buildPrayerListContainer(g['id'] as String, churchId, departmentId)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPrayerListContainer(String groupId, String churchId, String departmentId) {
    if (groupId == 'all') {
      return _buildAllTabExpandedView(departmentId, churchId);
    }
    return _buildSingleGroupView(groupId, churchId);
  }

  Widget _buildAllTabExpandedView(String departmentId, String churchId) {
    if (departmentId.isEmpty || churchId.isEmpty) {
      return const Center(child: Text('소속 정보가 누락되었습니다.'));
    }
    return ref.watch(departmentWeeklyDataProvider('$departmentId:$churchId')).when(
      skipLoadingOnRefresh: true,
      data: (data) {
        final groups = List<Map<String, dynamic>>.from(data['groups']);
        final allPrayers = List<Map<String, dynamic>>.from(data['prayers']);
        
        if (allPrayers.isEmpty) {
          // [UI] 빈 화면이라도 당겨서 새로고침 가능하게 처리
          return RefreshIndicator(
            onRefresh: _refreshData,
            color: AppTheme.primaryViolet,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                 SizedBox(height: 100),
                 Center(child: Text('등록된 기도제목이 없습니다.')),
              ],
            ),
          );
        }

        // [SORT] 클라이언트 사이드 부부 정렬 보강
        allPrayers.sort((a, b) {
          final m1 = a['member_directory'] ?? {};
          final m2 = b['member_directory'] ?? {};
          final f1 = (m1['family_name'] as String?)?.trim() ?? '';
          final f2 = (m2['family_name'] as String?)?.trim() ?? '';
          
          if (f1.isNotEmpty && f2.isEmpty) return -1;
          if (f1.isEmpty && f2.isNotEmpty) return 1;
          if (f1.isNotEmpty && f2.isNotEmpty && f1 != f2) return f1.compareTo(f2);
          
          final n1 = (m1['full_name'] as String?)?.trim() ?? '';
          final n2 = (m2['full_name'] as String?)?.trim() ?? '';
          return n1.compareTo(n2);
        });

        return RefreshIndicator(
          onRefresh: _refreshData,
          color: AppTheme.primaryViolet,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final gId = group['id'];
              final gName = group['name'];
              final groupPrayers = allPrayers.where((p) => p['group_id'] == gId).toList();
              
              if (groupPrayers.isEmpty) return const SizedBox.shrink();

              return Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), // v1 타일 패딩 추가
                  title: Text(
                    '$gName (${groupPrayers.length})', 
                    style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryViolet, fontSize: 16)
                  ),
                  childrenPadding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 12), // v1 그룹 헤더와 첫 카드 사이 여백 추가
                    ...groupPrayers.map((prayer) {
                      return _buildPrayerItemInList(prayer, gId, churchId, gName);
                    }),
                  ],
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('데이터 로딩 실패: $e')),
    );
  }

  Widget _buildSingleGroupView(String groupId, String churchId) {
    return ref.watch(weeklyDataProvider('$groupId:$churchId')).when(
      skipLoadingOnRefresh: true,
      data: (weeklyData) {
        final prayers = List<Map<String, dynamic>>.from(weeklyData['prayers']);
        final publishedPrayers = prayers.where((p) => p['status'] == 'published').toList();
        
        if (publishedPrayers.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refreshData,
            color: AppTheme.primaryViolet,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 100),
                Center(child: Text('아직 등록된 기도제목이 없습니다.')),
              ],
            ),
          );
        }

        // [SORT] 클라이언트 사이드 부부 정렬 보강
        publishedPrayers.sort((a, b) {
          final m1 = a['member_directory'] ?? {};
          final m2 = b['member_directory'] ?? {};
          final f1 = (m1['family_name'] as String?)?.trim() ?? '';
          final f2 = (m2['family_name'] as String?)?.trim() ?? '';
          
          if (f1.isNotEmpty && f2.isEmpty) return -1;
          if (f1.isEmpty && f2.isNotEmpty) return 1;
          if (f1.isNotEmpty && f2.isNotEmpty && f1 != f2) return f1.compareTo(f2);
          
          final n1 = (m1['full_name'] as String?)?.trim() ?? '';
          final n2 = (m2['full_name'] as String?)?.trim() ?? '';
          return n1.compareTo(n2);
        });

        final groupInfo = _allGroups.firstWhere((g) => (g['id'] ?? g['group_id']) == groupId, orElse: () => {});
        final gName = groupInfo['name'] ?? groupInfo['group_name'] ?? '';

        return RefreshIndicator(
          onRefresh: _refreshData,
          color: AppTheme.primaryViolet,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40), // v1 상단 24px로 확대
            itemCount: publishedPrayers.length,
            itemBuilder: (context, index) {
              return _buildPrayerItemInList(publishedPrayers[index], groupId, churchId, gName);
            },
          ),
        );
      },
      loading: () => Center(child: ShadcnSpinner()),
      error: (e, s) => Center(child: Text('기도제목 로딩 실패: $e')),
    );
  }

  Widget _buildPrayerItemInList(Map<String, dynamic> prayer, String groupId, String churchId, String groupName) {
    return ref.watch(groupMembersProvider(groupId)).when(
      data: (members) {
        final dirId = prayer['directory_member_id'];
        final memberInfo = members.firstWhere(
          (m) => m['id'] == dirId,
          orElse: () => {'full_name': '알 수 없음'}
        );
        final String memberName = memberInfo['full_name'] ?? '알 수 없음';
        final String profileId = memberInfo['profile_id'] ?? '';

        return PrayerCard(
          key: ValueKey(prayer['id']?.toString() ?? 'unknown_${prayer.hashCode}'),
          prayerId: (prayer['id'] ?? '').toString(),
          profileId: profileId,
          name: memberName,
          groupName: groupName.toString(),
          content: (prayer['content'] ?? '').toString(),
          togetherCount: prayer['together_count'] ?? 0,
        );
      },
      loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      error: (e, s) => Text('로딩 실패: $e'),
    );
  }
}

