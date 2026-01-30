import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/search/presentation/screens/search_screen.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

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
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              '소속 부서 정보가 없습니다.\n관리자 페이지에서 부서를 설정해 주세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textSub),
                            ),
                          ),
                        );
                      }

                      return ref.watch(departmentGroupsProvider(deptId)).when(
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

        return _PrayerCard(
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

class _PrayerCard extends ConsumerStatefulWidget {
  final String prayerId;
  final String groupName;
  final String name;
  final String profileId;
  final String content;
  final int togetherCount;
  const _PrayerCard({
    super.key,
    required this.prayerId,
    required this.groupName, 
    required this.name, 
    required this.profileId,
    required this.content,
    this.togetherCount = 0,
  });

  @override
  ConsumerState<_PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends ConsumerState<_PrayerCard> {
  bool _isExpanded = false;
  bool _isToggling = false;
  
  bool _optimisticPraying = false;
  bool _optimisticSaved = false;
  int _optimisticCount = 0;

  @override
  void didUpdateWidget(_PrayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isToggling && widget.togetherCount == _optimisticCount) {
      setState(() => _isToggling = false);
    }
  }

  Future<void> _toggleInteraction(String type) async {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;

    final interactions = ref.read(prayerInteractionsProvider(profile.id)).valueOrNull ?? [];
    final bool currentPraying = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'pray');
    final bool currentSaved = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'save');

    setState(() {
      _isToggling = true;
      if (type == 'pray') {
        _optimisticPraying = !currentPraying;
        _optimisticSaved = currentSaved;
        _optimisticCount = widget.togetherCount + (_optimisticPraying ? 1 : -1);
      } else {
        _optimisticSaved = !currentSaved;
        _optimisticPraying = currentPraying;
        _optimisticCount = widget.togetherCount;
      }
    });

    try {
      await ref.read(repositoryProvider).togglePrayerInteraction(
        prayerId: widget.prayerId,
        profileId: profile.id,
        type: type,
      );
      
      ref.invalidate(prayerInteractionsProvider(profile.id));
      await ref.read(prayerInteractionsProvider(profile.id).future);
      ref.invalidate(savedPrayersProvider(profile.id));
      
      if (type == 'pray') {
        ref.invalidate(weeklyDataProvider);
        ref.invalidate(departmentWeeklyDataProvider);
      } else {
        if (mounted) setState(() => _isToggling = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isToggling = false);
        SnackBarUtil.showSnackBar(
          context,
          message: '동작에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    }
  }

  Future<void> _showEditBottomSheet() async {
    final controller = TextEditingController(text: widget.content);
    final newContent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('기도제목 수정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSub),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 8,
              style: const TextStyle(fontSize: 16, height: 1.6),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.background,
                hintText: '내용을 입력해주세요',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: AppTheme.primaryViolet,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('저장하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (newContent != null && newContent.trim() != widget.content.trim()) {
      try {
        await Supabase.instance.client
            .from('prayer_entries')
            .update({'content': newContent.trim()})
            .eq('id', widget.prayerId);
        
        if (!mounted) return;
        SnackBarUtil.showSnackBar(context, message: '수정되었습니다.');
        ref.invalidate(weeklyDataProvider);
        ref.invalidate(departmentWeeklyDataProvider);
      } catch (e) {
        if (!mounted) return;
        SnackBarUtil.showSnackBar(
          context,
          message: '수정에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final interactionsAsync = profile != null 
        ? ref.watch(prayerInteractionsProvider(profile.id))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);
    
    final interactions = interactionsAsync.valueOrNull ?? [];
    final bool actualPraying = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'pray');
    final bool actualSaved = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'save');
    
    final bool displayPraying = _isToggling ? _optimisticPraying : actualPraying;
    final bool displaySaved = _isToggling ? _optimisticSaved : actualSaved;
    final int displayCount = _isToggling ? (_optimisticCount < 0 ? 0 : _optimisticCount) : widget.togetherCount;

    final String content = widget.content;
    final bool isLong = content.length > 80;

    return Container(
      margin: const EdgeInsets.only(bottom: 16), // v0 간격 최적화
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20), // v0 더 얄상한 곡률
        border: Border.all(color: const Color(0xFFE2E8F0)), // v0 명확한 색상
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), // v0 패딩 16px
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20, // 40x40
                  backgroundColor: AppTheme.primaryViolet.withOpacity(0.1),
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0] : '?', 
                    style: const TextStyle(color: AppTheme.primaryViolet, fontWeight: FontWeight.bold, fontSize: 14)
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'Pretendard')),
                      if (widget.groupName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(widget.groupName, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontFamily: 'Pretendard')),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _showEditBottomSheet,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(lucide.LucideIcons.moreHorizontal, size: 20, color: Color(0xFF94A3B8)), // v0 아이콘 변경 및 색상
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), // v0 본문 패딩 조정
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content,
                  maxLines: _isExpanded ? null : 3,
                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, height: 1.5, color: Color(0xFF334155), fontFamily: 'Pretendard'), // v0 정밀 텍스트
                ),
                if (isLong)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _isExpanded ? '접기' : '...더보기',
                        style: const TextStyle(color: AppTheme.primaryViolet, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)), // v0 아주 연한 구분선
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // v0 버튼 영역 슬림화
            child: Row(
              children: [
                InkWell(
                  onTap: _isToggling ? null : () => _toggleInteraction('pray'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), // 보관하기와 동일한 패딩
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          displayPraying ? Icons.favorite : lucide.LucideIcons.heart, 
                          size: 18, // 보관하기와 동일한 사이즈
                          color: displayPraying ? AppTheme.primaryViolet : const Color(0xFF94A3B8), // 보관하기와 동일한 컬러
                        ),
                        const SizedBox(width: 4), // 보관하기와 동일한 간격
                        Text(
                          displayPraying ? '함께 기도 중' : '함께 기도하기', 
                          style: TextStyle(
                            fontSize: 12.5, // 보관하기와 동일한 사이즈
                            color: displayPraying ? AppTheme.primaryViolet : const Color(0xFF94A3B8), // 보관하기와 동일한 컬러
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                        if (displayCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: displayPraying ? AppTheme.primaryViolet : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$displayCount', 
                              style: TextStyle(
                                fontSize: 10, 
                                color: displayPraying ? Colors.white : const Color(0xFF64748B),
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Pretendard',
                              )
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _isToggling ? null : () => _toggleInteraction('save'),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          displaySaved ? Icons.bookmark : lucide.LucideIcons.bookmark, // v0 채워진 북마크 적용
                          size: 18, 
                          color: displaySaved ? AppTheme.primaryViolet : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displaySaved ? '보관 중' : '보관하기',
                          style: TextStyle(
                            fontSize: 12.5, 
                            color: displaySaved ? AppTheme.primaryViolet : const Color(0xFF94A3B8), 
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
