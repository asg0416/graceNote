import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snack_bar_util.dart';

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

      final results = await ref.read(repositoryProvider).searchPrayers(
        churchId: profile.churchId ?? '',
        departmentId: profile.departmentId,
        groupId: finalGroupId,
        date: _selectedDate,
        searchTerm: _searchController.text,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
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
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryIndigo,
              onPrimary: Colors.white,
              onSurface: AppTheme.textMain,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _performSearch();
    }
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
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
                  loading: () => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (e, s) => const Text('로드 실패'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : !_searchInitiated 
                ? _buildInitialState() // 검색 전 안내 문구
                : _searchResults.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final prayer = _searchResults[index];
                      return _PrayerCard(
                        key: ValueKey(prayer['id']),
                        prayerId: prayer['id'],
                        name: prayer['member_directory']['full_name'] ?? '알 수 없음',
                        groupName: prayer['member_directory']['group_name'] ?? '',
                        profileId: prayer['member_id'] ?? '',
                        content: prayer['content'] ?? '',
                        togetherCount: prayer['together_count'] ?? 0,
                        date: prayer['weeks']['week_date'],
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
            style: TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold)),
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
        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textLight),
        suffixIcon: _searchController.text.isNotEmpty 
          ? IconButton(
              icon: const Icon(Icons.cancel_rounded, color: AppTheme.textLight, size: 20),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildDateFilter() {
    return InkWell(
      onTap: () => _selectDate(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _selectedDate != null ? AppTheme.primaryIndigo : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: _selectedDate != null ? AppTheme.primaryIndigo : AppTheme.textLight),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedDate == null ? '전체 날짜' : DateFormat('yyyy.MM.dd').format(_selectedDate!),
                style: TextStyle(
                  color: _selectedDate != null ? AppTheme.primaryIndigo : AppTheme.textSub,
                  fontSize: 13,
                  fontWeight: _selectedDate != null ? FontWeight.bold : FontWeight.normal,
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
                child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.primaryIndigo),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupFilter(List<Map<String, dynamic>> groups) {
    final allGroups = [{'id': 'all', 'name': '전체 조'}, ...groups];
    
    // 현재 선택된 ID가 목록에 없으면 'all'로 리셋
    if (!allGroups.any((g) => g['id'] == _selectedGroupId)) {
      _selectedGroupId = 'all';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGroupId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textLight),
          items: allGroups.map((g) => DropdownMenuItem(
            value: g['id'] as String, 
            child: Text(g['name'] as String, style: const TextStyle(fontSize: 13))
          )).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedGroupId = val);
              _performSearch();
            }
          },
        ),
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
          const Text('검색 결과가 없습니다', style: TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Search용 전용 PrayerCard (일부 기능 간소화 및 날짜 표시 추가)
// -----------------------------------------------------------------------------
class _PrayerCard extends ConsumerStatefulWidget {
  final String prayerId;
  final String groupName;
  final String name;
  final String profileId;
  final String content;
  final int togetherCount;
  final String? date;

  const _PrayerCard({
    super.key,
    required this.prayerId,
    required this.groupName, 
    required this.name, 
    required this.profileId,
    required this.content,
    this.togetherCount = 0,
    this.date,
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
      ref.invalidate(savedPrayersProvider(profile.id));
      
      if (mounted) setState(() => _isToggling = false);
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

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final interactions = profile != null 
        ? ref.watch(prayerInteractionsProvider(profile.id)).valueOrNull ?? []
        : <Map<String, dynamic>>[];
    
    final bool actualPraying = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'pray');
    final bool actualSaved = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'save');
    
    final bool displayPraying = _isToggling ? _optimisticPraying : actualPraying;
    final bool displaySaved = _isToggling ? _optimisticSaved : actualSaved;
    final int displayCount = _isToggling ? (_optimisticCount < 0 ? 0 : _optimisticCount) : widget.togetherCount;
    
    final bool isLong = widget.content.length > 80;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primaryIndigo.withOpacity(0.1),
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0] : '?', 
                    style: const TextStyle(color: AppTheme.primaryIndigo, fontWeight: FontWeight.bold, fontSize: 13)
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          const SizedBox(width: 8),
                          if (widget.date != null)
                            Text(
                              widget.date!, 
                              style: const TextStyle(color: AppTheme.textLight, fontSize: 11, fontWeight: FontWeight.bold)
                            ),
                        ],
                      ),
                      if (widget.groupName.isNotEmpty)
                        Text(widget.groupName, style: const TextStyle(color: AppTheme.textSub, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.content,
                  maxLines: _isExpanded ? null : 3,
                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.6, color: AppTheme.textMain),
                ),
                if (isLong)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _isExpanded ? '접기' : '...더보기',
                        style: const TextStyle(color: AppTheme.primaryIndigo, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                InkWell(
                  onTap: _isToggling ? null : () => _toggleInteraction('pray'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          displayPraying ? Icons.volunteer_activism_rounded : Icons.volunteer_activism_outlined,
                          size: 18, 
                          color: displayPraying ? AppTheme.primaryIndigo : AppTheme.textSub
                        ),
                        const SizedBox(width: 8),
                        Text(
                          displayPraying ? '함께 기도 중' : '같이 기도',
                          style: TextStyle(
                            fontSize: 12, 
                            color: displayPraying ? AppTheme.primaryIndigo : AppTheme.textSub,
                            fontWeight: FontWeight.w800
                          ),
                        ),
                        if (displayCount > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '$displayCount',
                            style: const TextStyle(fontSize: 11, color: AppTheme.primaryIndigo, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _isToggling ? null : () => _toggleInteraction('save'),
                  icon: Icon(
                    displaySaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    size: 18, 
                    color: displaySaved ? AppTheme.primaryIndigo : AppTheme.textSub,
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
