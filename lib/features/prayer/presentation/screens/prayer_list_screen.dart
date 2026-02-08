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
  String _sortBy = 'name'; // 'name' 또는 'latest'

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
    ref.invalidate(userGroupsProvider);
    final groups = await ref.read(userGroupsProvider.future);
    
    final profile = ref.read(userProfileProvider).value;
    if (profile != null && profile.churchId != null) {
      ref.invalidate(weekIdProvider(profile.churchId!));
    }

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

  // [FIX] 유효한 주차(DB에 있는 주차)로만 이동
  void _moveWeek(int direction) {
    // 1. 현재 교회 ID 가져오기
    final profile = ref.read(userProfileProvider).value;
    if (profile?.churchId == null) return;

    // 2. 가용한 주차 목록 가져오기 (비동기 상태일 수 있으므로 동기적으로 읽을 수 있는지 확인)
    //    이미 화면이 그려진 상태라면 provider가 값을 가지고 있을 가능성이 높음
    final weeksAsync = ref.read(availableWeeksProvider(profile!.churchId!));
    
    weeksAsync.whenData((weeks) {
      if (weeks.isEmpty) return;

      final current = ref.read(selectedWeekDateProvider);
      // week_date와 current가 시,분,초 차이로 다를 수 있으므로 날짜만 비교
      final currentDateOnly = DateTime(current.year, current.month, current.day);

      // weeks는 내림차순(최신순) 정렬되어 있음 -> [2024-02-11, 2024-02-04, ...]
      // currentIndex 찾기
      int currentIndex = -1;
      for (int i = 0; i < weeks.length; i++) {
        final w = weeks[i];
        if (w.year == currentDateOnly.year && w.month == currentDateOnly.month && w.day == currentDateOnly.day) {
          currentIndex = i;
          break;
        }
      }

      // 현재 날짜가 리스트에 없다면(예: 생성되지 않은 이번주) 리스트에 임시 추가해서 위치 계산
      // 단, 이번 로직은 "생성된 주차"만 탐색이므로, 만약 현재 날짜가 리스트에 없다면 가장 가까운 날짜로 이동 등을 고려해야 하지만,
      // 초기 진입 시점에 이미 availableWeeks의 첫 번째 값(최신)으로 세팅하거나 해야 함.
      // 여기서는 현재 날짜가 리스트에 없으면 아무 동작 안하거나 가장 최신으로 이동
      if (currentIndex == -1) {
        // 예외 처리: 현재 날짜가 유효 목록에 없으면 가장 최신(0번)으로 이동
        ref.read(selectedWeekDateProvider.notifier).state = weeks.first;
        return;
      }

      // direction: -1 (이전, 과거), +1 (다음, 미래)
      // 리스트가 내림차순(미래 -> 과거)이므로:
      // 이전(과거)로 가려면 인덱스 증가 (+1)
      // 다음(미래)로 가려면 인덱스 감소 (-1)
      
      // 화살표 방향과 리스트 인덱스 방향이 반대임에 유의
      // UI 상 왼쪽(<) 버튼은 '이전 주(과거)' -> moveWeek(-1) 호출
      // UI 상 오른쪽(>) 버튼은 '다음 주(미래)' -> moveWeek(1) 호출

      int nextIndex;
      if (direction < 0) {
        // 과거로 이동 (인덱스 증가)
        nextIndex = currentIndex + 1;
      } else {
        // 미래로 이동 (인덱스 감소)
        nextIndex = currentIndex - 1;
      }

      if (nextIndex >= 0 && nextIndex < weeks.length) {
        ref.read(selectedWeekDateProvider.notifier).state = weeks[nextIndex];
      }
    });
  }

  Widget _buildWeekNavigator(DateTime date) {
    final int weekNumber = ((date.day - 1) / 7).floor() + 1;
    final String weekStr = '${date.month}월 ${weekNumber}주차';
    
    final profile = ref.watch(userProfileProvider).value;
    final weeksAsync = profile?.churchId != null 
        ? ref.watch(availableWeeksProvider(profile!.churchId!)) 
        : const AsyncValue.data(<DateTime>[]);

    return weeksAsync.when(
      data: (weeks) {
        // 현재 날짜 매칭
        final currentDateOnly = DateTime(date.year, date.month, date.day);
        int currentIndex = -1;
        for (int i = 0; i < weeks.length; i++) {
          final w = weeks[i];
          if (w.year == currentDateOnly.year && w.month == currentDateOnly.month && w.day == currentDateOnly.day) {
            currentIndex = i;
            break;
          }
        }

        // 네비게이션 가능 여부 (weeks: 내림차순 [미래 ... 과거])
        // currentIndex가 -1이면(리스트에 없음) 네비게이션 불가 혹은 예외
        // 과거로 가기(<): 인덱스가 (length - 1)보다 작아야 함 (더 큰 인덱스가 있어야 함)
        // 미래로 가기(>): 인덱스가 0보다 커야 함 (더 작은 인덱스가 있어야 함)
        
        final bool canGoPrev = currentIndex != -1 && currentIndex < weeks.length - 1;
        final bool canGoNext = currentIndex != -1 && currentIndex > 0;

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: canGoPrev ? () => _moveWeek(-1) : null,
                icon: Icon(lucide.LucideIcons.chevronLeft, color: canGoPrev ? AppTheme.textSub : AppTheme.border, size: 18),
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
                                // [FIX] DB에 존재하는 주차만 선택 가능
                                selectableDayPredicate: (d) {
                                  return weeks.any((w) => 
                                    w.year == d.year && w.month == d.month && w.day == d.day
                                  );
                                },
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
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    weekStr,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                      fontFamily: 'Pretendard',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: canGoNext ? () => _moveWeek(1) : null,
                icon: Icon(lucide.LucideIcons.chevronRight, color: canGoNext ? AppTheme.textSub : AppTheme.border, size: 18),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 50, child: Center(child: CircularProgressIndicator())),
      error: (e, s) => SizedBox(height: 50, child: Center(child: Text('error: $e'))),
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 52,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: Icon(lucide.LucideIcons.listFilter, color: AppTheme.primaryViolet, size: 20),
              onSelected: (value) {
                setState(() {
                  _sortBy = value;
                });
              },
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'name',
                  child: Row(
                    children: [
                      Icon(lucide.LucideIcons.list, size: 18),
                      SizedBox(width: 8),
                      Text('조 이름순', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'latest',
                  child: Row(
                    children: [
                      Icon(lucide.LucideIcons.clock, size: 18),
                      SizedBox(width: 8),
                      Text('조 활동순', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ],
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
      'color_hex': g['color_hex'], // [NEW] 색상 정보 전달
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
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicator: BoxDecoration(
                color: const Color(0xFFF3F0FF),
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              labelColor: const Color(0xFF7C3AED),
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

// [FIX] ListView 스크롤 시 아코디언 상태 초기화 방지
  final Map<String, bool> _expandedStates = {};

  // ... (existing code)

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

        // [SORT] 전체 기도 목록 정렬 로직 (Marriage Key Sort)
        allPrayers.sort((a, b) {
          final m1 = a['member_directory'] ?? {};
          final m2 = b['member_directory'] ?? {};
          
          String getMarriageKey(Map<String, dynamic> m) {
            final name = (m['full_name'] as String?)?.trim() ?? '';
            final spouse = (m['spouse_name'] as String?)?.trim() ?? '';
            
            if (spouse.isEmpty) return name;
            
            // 이름과 배우자 이름을 가나다순으로 정렬하여 키 생성
            // 예: "김철수", 배우자 "이영희" -> "김철수_이영희"
            // 예: "이영희", 배우자 "김철수" -> "김철수_이영희" (동일 키 발생 -> 묶임)
            final list = [name, spouse];
            list.sort(); 
            return list.join('_');
          }
          
          final k1 = getMarriageKey(m1);
          final k2 = getMarriageKey(m2);
          
          if (k1 != k2) return k1.compareTo(k2);
          
          // 키가 같으면(부부) 이름순 정렬 (보통 가나다순, 남편/아내 구분 필드가 없으므로 이름순)
          final n1 = (m1['full_name'] as String?)?.trim() ?? '';
          final n2 = (m2['full_name'] as String?)?.trim() ?? '';
          return n1.compareTo(n2);
        });

        // [SORT] 전체 부서의 조(Group) 목록 정렬
        if (_sortBy == 'name') {
          groups.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        } else if (_sortBy == 'latest') {
          groups.sort((a, b) {
            final gIdA = (a['id'] ?? '').toString();
            final gIdB = (b['id'] ?? '').toString();
            
            // 각 조별 가장 최신 기도제목의 시간 찾기
            final latestA = allPrayers
                .where((p) => p['group_id'] == gIdA)
                .map((p) => DateTime.parse(p['created_at'] ?? '2000-01-01'))
                .fold(DateTime(2000), (prev, curr) => curr.isAfter(prev) ? curr : prev);
            
            final latestB = allPrayers
                .where((p) => p['group_id'] == gIdB)
                .map((p) => DateTime.parse(p['created_at'] ?? '2000-01-01'))
                .fold(DateTime(2000), (prev, curr) => curr.isAfter(prev) ? curr : prev);
            
            return latestB.compareTo(latestA); // 최신이 위로
          });
        }

        return RefreshIndicator(
          onRefresh: _refreshData,
          color: AppTheme.primaryViolet,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final gId = (group['id'] ?? '').toString(); 
              final gName = group['name'];
              final gColor = _parseColor(group['color_hex']);
              final groupPrayers = allPrayers.where((p) => p['group_id'] == gId).toList();
              
              if (groupPrayers.isEmpty) return const SizedBox.shrink();

              // [SORT] 조 내부 정렬 (Marriage Key Sort)
              groupPrayers.sort((a, b) {
                final m1 = a['member_directory'] ?? {};
                final m2 = b['member_directory'] ?? {};
                
                String getMarriageKey(Map<String, dynamic> m) {
                  final name = (m['full_name'] as String?)?.trim() ?? '';
                  final spouse = (m['spouse_name'] as String?)?.trim() ?? '';
                  if (spouse.isEmpty) return name;
                  final list = [name, spouse];
                  list.sort(); 
                  return list.join('_');
                }
                
                final k1 = getMarriageKey(m1);
                final k2 = getMarriageKey(m2);
                
                if (k1 != k2) return k1.compareTo(k2);
                
                final n1 = (m1['full_name'] as String?)?.trim() ?? '';
                final n2 = (m2['full_name'] as String?)?.trim() ?? '';
                return n1.compareTo(n2);
              });

              // 상태가 없으면 기본값 true (펼침)
              final isExpanded = _expandedStates[gId] ?? true;

              return Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: PageStorageKey('group_expansion_$gId'), // [FIX] 상태 보존을 위한 키 추가
                  initiallyExpanded: isExpanded,
                  onExpansionChanged: (expanded) {
                    _expandedStates[gId] = expanded; // 상태 저장 (setState 불필요, 다음 빌드 시 적용됨)
                  },
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  title: Text(
                    '$gName (${groupPrayers.length})', 
                    style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryViolet, fontSize: 16)
                  ),
                  childrenPadding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 12),
                    ...groupPrayers.map((prayer) {
                      return _buildPrayerItemInList(prayer, gId, churchId, gName, groupColor: gColor); // [NEW] 색상 전달
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

         // [SORT] 이름순(부부순) 정렬 (Marriage Key Sort)
        publishedPrayers.sort((a, b) {
          final m1 = a['member_directory'] ?? {};
          final m2 = b['member_directory'] ?? {};
          
          String getMarriageKey(Map<String, dynamic> m) {
            final name = (m['full_name'] as String?)?.trim() ?? '';
            final spouse = (m['spouse_name'] as String?)?.trim() ?? '';
            if (spouse.isEmpty) return name;
            final list = [name, spouse];
            list.sort(); 
            return list.join('_');
          }
          
          final k1 = getMarriageKey(m1);
          final k2 = getMarriageKey(m2);
          
          if (k1 != k2) return k1.compareTo(k2);
          
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
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            itemCount: publishedPrayers.length,
            itemBuilder: (context, index) {
              final gColor = _parseColor(groupInfo['color_hex']); // [NEW] 단일 조 뷰에서도 색상 적용
              return _buildPrayerItemInList(publishedPrayers[index], groupId, churchId, gName, groupColor: gColor);
            },
          ),
        );
      },
      loading: () => Center(child: ShadcnSpinner()),
      error: (e, s) => Center(child: Text('기도제목 로딩 실패: $e')),
    );
  }

  Color? _parseColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return null;
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  Widget _buildPrayerItemInList(Map<String, dynamic> prayer, String groupId, String churchId, String groupName, {Color? groupColor}) {
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
          isDraft: prayer['status'] != 'published',
          togetherCount: prayer['together_count'] ?? 0,
          groupColor: groupColor, // [NEW] PrayerCard에 색상 전달
        );
      },
      loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      error: (e, s) => Text('로딩 실패: $e'),
    );
  }
}
