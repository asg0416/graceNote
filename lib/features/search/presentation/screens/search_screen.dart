import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:grace_note/features/prayer/presentation/widgets/prayer_card.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;
import 'package:lucide_icons/lucide_icons.dart' as lucide;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDate;
  String _selectedGroupId = 'all';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  bool _searchInitiated = false;

  @override
  void initState() {
    super.initState();
    // 초기 검색 제거 (사용자가 검색을 시작할 때까지는 비워둠)
  }

  Future<void> _performSearch() async {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;

    setState(() {
      _isLoading = true;
      _searchInitiated = true; // 검색이 시작됨을 표시
    });

    try {
      final userGroups = ref.read(userGroupsProvider).value ?? [];
      final isLeaderOrAdmin = userGroups.any((g) => g['role_in_group'] == 'leader' || g['role_in_group'] == 'admin') ||
                             profile.role == 'admin' || profile.isMaster;
      
      String finalGroupId = _selectedGroupId;
      if (!isLeaderOrAdmin && userGroups.isNotEmpty) {
        // 조원은 본인 소속 조 ID로 강제 고정
        finalGroupId = userGroups.first['group_id'];
      }

      final List<Map<String, dynamic>> results = await ref.read(repositoryProvider).searchPrayers(
        churchId: profile.churchId ?? '',
        departmentId: profile.departmentId,
        groupId: finalGroupId,
        date: _selectedDate,
        searchTerm: _searchController.text,
      );

      final List<Map<String, dynamic>> sortedResults = List<Map<String, dynamic>>.from(results);
      // [SORT] 클라이언트 사이드 부부 정렬 보강
      sortedResults.sort((a, b) {
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

      if (mounted) {
        setState(() {
          _searchResults = sortedResults;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarUtil.showSnackBar(
          context,
          message: '검색에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    }
  }
// ... (selectDate 메서드는 동일하므로 생략하거나 아래에서 context 유지)
  Future<void> _selectDate(BuildContext context) async {
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
                  child: Text('검색 날짜 선택 (일요일)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textMain, fontFamily: 'Pretendard')),
                ),
                const Divider(height: 24),
                shad.ShadCalendar(
                  selected: _selectedDate,
                  weekStartsOn: 7,
                  selectableDayPredicate: (date) {
                    final profile = ref.read(userProfileProvider).value;
                    if (profile?.churchId == null) return false;
                    
                    // 동기적으로 provider 값을 읽어옴 (이미 로드되었을 가능성 높음)
                    // 만약 로드되지 않았다면 기본적으로 false가 되어 선택 등 불가하거나,
                    // 사용자 경험상 로딩 스피너를 보여주는게 맞지만, 
                    // 여기서는 간단히 availableWeeksProvider값 확인
                    final weeksAsync = ref.read(availableWeeksProvider(profile!.churchId!));
                    
                    if (weeksAsync.hasValue) {
                      return weeksAsync.value!.any((w) => 
                        w.year == date.year && w.month == date.month && w.day == date.day
                      );
                    }
                    return false;
                  },
                  onChanged: (newDate) {
                    if (newDate != null) {
                      setState(() => _selectedDate = newDate);
                      Navigator.pop(context);
                      _performSearch();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final groupsAsync = profile != null 
        ? ref.watch(departmentGroupsProvider(profile.departmentId ?? ''))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('기도제목 검색', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 20)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppTheme.border, height: 1.0),
        ),
        leading: IconButton(
          icon: const Icon(lucide.LucideIcons.chevronLeft, color: AppTheme.textMain, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Column(
              children: [
                _buildSearchInput(),
                const SizedBox(height: 16),
                groupsAsync.when(
                  data: (groups) {
                    final isLeaderOrAdmin = groups.any((g) => g['role_in_group'] == 'leader' || g['role_in_group'] == 'admin') ||
                                           (profile?.role == 'admin' || profile?.isMaster == true);
                    
                    if (!isLeaderOrAdmin) {
                      return _buildDateFilter(); // 조원은 날짜 필터만 표시
                    }

                    return Row(
                      children: [
                        Expanded(child: _buildDateFilter()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildGroupFilter(groups)),
                      ],
                    );
                  },
                  loading: () => SizedBox(height: 48, child: Center(child: ShadcnSpinner())),
                  error: (e, s) => const Text('로드 실패'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading 
              ? Center(child: ShadcnSpinner())
              : !_searchInitiated 
                ? _buildInitialState() // 검색 전 안내 문구
                : _searchResults.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final prayer = _searchResults[index];
                      return PrayerCard(
                        key: ValueKey(prayer['id']),
                        prayerId: prayer['id'].toString(),
                        name: prayer['member_directory']['full_name'] ?? '알 수 없음',
                        groupName: prayer['member_directory']['group_name'] ?? '',
                        profileId: prayer['member_directory']['profile_id'] ?? prayer['member_id'] ?? '',
                        content: prayer['content'] ?? '',
                        togetherCount: prayer['together_count'] ?? 0,
                        date: prayer['weeks'] != null ? prayer['weeks']['week_date'] : null,
                        onInteractionToggle: (type, isPositive) {
                          if (type == 'pray') {
                            setState(() {
                              prayer['together_count'] = (prayer['together_count'] ?? 0) + (isPositive ? 1 : -1);
                            });
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: 64, color: AppTheme.divider),
          const SizedBox(height: 16),
          const Text('이름이나 기도내용을 입력하여 검색해 보세요', 
            style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSearchInput() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 15),
      onSubmitted: (_) => _performSearch(),
      onChanged: (val) => setState(() {}), // X 버튼 표시 여부 갱신용
      decoration: InputDecoration(
        hintText: '이름이나 기도제목을 입력하세요',
        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSub),
        suffixIcon: _searchController.text.isNotEmpty 
          ? IconButton(
              icon: const Icon(Icons.cancel_rounded, color: AppTheme.textSub, size: 20),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchResults = [];
                  _searchInitiated = false;
                });
              },
            )
          : null,
        fillColor: AppTheme.background,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), 
          borderSide: const BorderSide(color: AppTheme.borderMedium)
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), 
          borderSide: const BorderSide(color: AppTheme.borderMedium)
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), 
          borderSide: const BorderSide(color: AppTheme.primaryViolet, width: 2)
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
    return InkWell(
      onTap: () => _selectDate(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 48, // v1 높이 고정
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _selectedDate != null ? AppTheme.primaryViolet : AppTheme.borderMedium),
        ),
        child: Row(
          children: [
            Icon(lucide.LucideIcons.calendar, size: 16, color: _selectedDate != null ? AppTheme.primaryViolet : AppTheme.textSub),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedDate == null ? '전체 날짜' : DateFormat('yyyy.MM.dd').format(_selectedDate!),
                style: TextStyle(
                  color: _selectedDate != null ? AppTheme.primaryViolet : AppTheme.textSub,
                  fontSize: 13,
                  fontWeight: _selectedDate != null ? FontWeight.w700 : FontWeight.w500,
                  fontFamily: 'Pretendard',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedDate != null)
              GestureDetector(
                onTap: () {
                  setState(() => _selectedDate = null);
                  _performSearch();
                },
                child: const Icon(lucide.LucideIcons.x, size: 14, color: AppTheme.textSub),
              ),
          ],
        ),
      ),
    );
  }

  String _groupSearchQuery = '';

  Widget _buildGroupFilter(List<Map<String, dynamic>> groups) {
    final allGroups = [{'id': 'all', 'name': '전체 조'}, ...groups];
    final filteredGroups = allGroups.where((g) => 
      (g['name'] as String).toLowerCase().contains(_groupSearchQuery.toLowerCase())
    ).toList();
    
    // 현재 선택된 ID가 목록에 없으면 'all'로 리셋
    if (!allGroups.any((g) => g['id'] == _selectedGroupId)) {
      _selectedGroupId = 'all';
    }

    return SizedBox(
      height: 48,
      child: shad.ShadSelect<String>.withSearch(
        placeholder: const Text('조 선택', style: TextStyle(fontSize: 14, color: AppTheme.textSub, fontFamily: 'Pretendard')),
        initialValue: _selectedGroupId,
        minWidth: 120,
        maxHeight: 400,
        decoration: shad.ShadDecoration(
          color: AppTheme.background,
          border: shad.ShadBorder.all(
            radius: BorderRadius.circular(16),
            width: 1,
            color: AppTheme.borderMedium,
          ),
          shape: BoxShape.rectangle,
        ),
        onChanged: (val) {
          if (val != null) {
            setState(() => _selectedGroupId = val);
            _performSearch();
          }
        },
        selectedOptionBuilder: (context, value) {
          final group = allGroups.firstWhere((g) => g['id'] == value, orElse: () => allGroups.first);
          return Text(group['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textMain, fontFamily: 'Pretendard'));
        },
        options: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text('조 목록', style: TextStyle(fontSize: 12, color: AppTheme.textSub, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')),
          ),
          ...filteredGroups.map((g) => shad.ShadOption(
            value: g['id'] as String,
            child: Text(g['name'] as String, style: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w500, fontSize: 14)),
          )),
        ],
        searchPlaceholder: const Text('조 이름을 입력하세요', style: TextStyle(fontFamily: 'Pretendard', fontSize: 14)),
        onSearchChanged: (query) => setState(() => _groupSearchQuery = query),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: AppTheme.divider),
          const SizedBox(height: 16),
          const Text('검색 결과가 없습니다', style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
