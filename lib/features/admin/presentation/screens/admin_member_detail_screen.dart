import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMemberDetailScreen extends ConsumerStatefulWidget {
  final String directoryMemberId;
  final String fullName;
  final String groupName;
  final String groupId;
  final String departmentId;

  const AdminMemberDetailScreen({
    super.key,
    required this.directoryMemberId,
    required this.fullName,
    required this.groupName,
    required this.groupId,
    required this.departmentId,
  });

  @override
  ConsumerState<AdminMemberDetailScreen> createState() =>
      _AdminMemberDetailScreenState();
}

class _AdminMemberDetailScreenState
    extends ConsumerState<AdminMemberDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _personMemberships = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 15;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _fetchPersonMemberships();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      _fetchHistory();
    }
  }

  Future<void> _fetchHistory() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = ref.read(repositoryProvider);
      final newItems = await repository.getMemberPrayerHistory(
          widget.directoryMemberId,
          page: _page,
          pageSize: _pageSize);

      if (mounted) {
        setState(() {
          _history.addAll(newItems);
          _hasMore = newItems.length == _pageSize;
          _page++;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _fetchPersonMemberships() async {
    try {
      final client = Supabase.instance.client;
      final memberProfile = await client
          .from('member_profiles')
          .select('person_id')
          .eq('member_directory_id', widget.directoryMemberId)
          .maybeSingle();

      final personId = memberProfile?['person_id']?.toString();
      if (personId == null || personId.isEmpty) return;

      final response = await client
          .from('memberships')
          .select('role, status, groups(name), departments(name)')
          .eq('person_id', personId)
          .eq('status', 'active')
          .order('status', ascending: true);

      final memberships = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;
      setState(() => _personMemberships = memberships);
    } catch (e) {
      debugPrint(
          'AdminMemberDetailScreen: Phase 2 memberships read failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(departmentGroupsProvider(
        widget.departmentId)); // [NEW] Fetch groups to check New Family status
    return Scaffold(
      backgroundColor:
          const Color(0xFFF8F9FA), // Slightly off-white bg for cards to pop
      appBar: AppBar(
        title: const Text('구성원 상세 정보',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
                fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(color: Colors.white, child: _buildProfileCard()),
            // 등반 현황 카드 (새가족 조 일반 조원에게만)
            _buildClimbingStatusCard(groupsAsync),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: const Text('기도제목 히스토리',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMain)),
            ),

            if (_history.isEmpty && !_isLoading && _error == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('등록된 기도제목이 없습니다.',
                      style: TextStyle(color: AppTheme.textSub)),
                ),
              ),

            if (_error != null)
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('로딩 에러: $_error'))),

            ..._buildGroupedHistory(),

            if (_isLoading)
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: ShadcnSpinner())),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedHistory() {
    final List<Widget> widgets = [];
    String? lastYearMonth;

    for (var i = 0; i < _history.length; i++) {
      final prayer = _history[i];
      final weeksData = prayer['weeks'];
      final dateStr =
          weeksData != null ? weeksData['week_date'] : prayer['created_at'];
      final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();

      final currentYearMonth = DateFormat('yyyy.MM').format(date);

      if (lastYearMonth != currentYearMonth) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryViolet.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat('yyyy년 M월').format(date),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryViolet,
                        fontSize: 13),
                  ),
                ),
                const Expanded(
                    child: Divider(indent: 12, color: AppTheme.border)),
              ],
            ),
          ),
        );
        lastYearMonth = currentYearMonth;
      }

      widgets.add(_buildPrayerCard(prayer));
    }
    return widgets;
  }

  Widget _buildProfileCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppTheme.primaryViolet.withOpacity(0.1),
            child: Text(
              widget.fullName.length >= 2
                  ? widget.fullName.substring(widget.fullName.length - 2)
                  : widget.fullName,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryViolet),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.fullName,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(widget.groupName,
                    style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w600)),
                if (_personMemberships.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _personMemberships.map((membership) {
                      final department = membership['departments'];
                      final group = membership['groups'];
                      final departmentName =
                          department is Map ? department['name'] : null;
                      final groupName = group is Map ? group['name'] : null;
                      final role = membership['role'] == 'leader' ? '조장' : '조원';
                      final label = [
                        if (departmentName != null) departmentName,
                        if (groupName != null) groupName,
                      ].join(' / ');

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryViolet.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: AppTheme.primaryViolet
                                  .withValues(alpha: 0.18)),
                        ),
                        child: Text(
                          '$label · $role',
                          style: const TextStyle(
                            color: AppTheme.primaryViolet,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClimbingStatusCard(
      AsyncValue<List<Map<String, dynamic>>> groupsAsync) {
    return groupsAsync.when(
      data: (groups) {
        final currentGroup = groups.cast<Map<String, dynamic>?>().firstWhere(
              (g) => g?['name'] == widget.groupName,
              orElse: () => null,
            );

        if (currentGroup == null ||
            !(currentGroup['is_new_member_group'] ?? false)) {
          return const SizedBox.shrink();
        }

        final groupId = currentGroup['id'] as String?;
        final threshold = currentGroup['climbing_threshold'] ?? 4;

        return FutureBuilder<Map<String, dynamic>?>(
          future: ref
              .read(repositoryProvider)
              .getDirectoryMember(widget.directoryMemberId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final memberData = snapshot.data;
            final role = memberData?['role_in_group'];

            // 조장에게는 등반 카드 비노출
            if (role == 'leader') return const SizedBox.shrink();

            return Consumer(
              builder: (context, ref, _) {
                final progressAsync = groupId != null
                    ? ref.watch(memberClimbingProgressProvider(
                        '${widget.directoryMemberId}:$groupId'))
                    : const AsyncValue<int>.data(0);

                return progressAsync.when(
                  data: (count) {
                    final isComplete = count >= threshold;
                    final progress = (count / threshold).clamp(0.0, 1.0);

                    return Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 상단: 라벨 + 배지 + 버튼
                          Row(
                            children: [
                              Icon(
                                isComplete
                                    ? LucideIcons.circleCheck
                                    : LucideIcons.trendingUp,
                                size: 18,
                                color: AppTheme.textMain,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '등반 현황',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMain,
                                  fontFamily: 'Pretendard',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isComplete
                                      ? const Color(0xFF22C55E)
                                          .withValues(alpha: 0.1)
                                      : const Color(0xFFF472B6)
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$count / $threshold회',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isComplete
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFEC4899),
                                    fontFamily: 'Pretendard',
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // 조 이동 / 등반 처리 버튼
                              GestureDetector(
                                onTap: _showMoveGroupDialog,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryViolet
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppTheme.primaryViolet
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(LucideIcons.arrowLeftRight,
                                          size: 14,
                                          color: AppTheme.primaryViolet),
                                      const SizedBox(width: 6),
                                      const Text(
                                        '조 편성',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primaryViolet,
                                          fontFamily: 'Pretendard',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 하단: 프로그레스 바
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: AppTheme.primaryViolet
                                  .withValues(alpha: 0.08),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppTheme.primaryViolet,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildPrayerCard(Map<String, dynamic> prayer) {
    final title = (prayer['title'] ?? '') as String;
    final content = (prayer['content'] ?? '') as String;

    // 주차 날짜 계산
    String dateDisplay = '';
    final weeksData = prayer['weeks'];
    if (weeksData != null && weeksData['week_date'] != null) {
      final date = DateTime.parse(weeksData['week_date']);
      // "1/4" 등으로 날짜만 심플하게 표시 (주차 텍스트 제거)
      dateDisplay = DateFormat('M/d').format(date);
    } else {
      final createdAt = DateTime.parse(prayer['created_at']);
      dateDisplay = DateFormat('M/d').format(createdAt);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 14, color: AppTheme.primaryViolet),
                SizedBox(width: 6),
                Text(dateDisplay,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.textMain)),
              ],
            ),
            const SizedBox(height: 12),
            if (title.isNotEmpty) ...[
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.textMain)),
              const SizedBox(height: 6),
            ],
            Text(
              content,
              style: const TextStyle(
                  color: AppTheme.textSub, fontSize: 15, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoveGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => _MoveGroupDialog(
        departmentId: widget.departmentId,
        currentGroupId: widget.groupId,
        currentGroupName: widget.groupName,
        directoryMemberId: widget.directoryMemberId,
        memberFullName: widget.fullName,
      ),
    );
  }
}

class _MoveGroupDialog extends ConsumerStatefulWidget {
  final String departmentId;
  final String currentGroupId;
  final String currentGroupName;
  final String directoryMemberId;
  final String memberFullName;

  const _MoveGroupDialog({
    super.key,
    required this.departmentId,
    required this.currentGroupId,
    required this.currentGroupName,
    required this.directoryMemberId,
    required this.memberFullName,
  });

  @override
  ConsumerState<_MoveGroupDialog> createState() => _MoveGroupDialogState();
}

class _MoveGroupDialogState extends ConsumerState<_MoveGroupDialog> {
  String? _selectedGroupId;
  bool _isSaving = false;
  String _groupSearchQuery = '';

  @override
  Widget build(BuildContext context) {
    final groupsAsync =
        ref.watch(departmentGroupsProvider(widget.departmentId));

    return ShadDialog(
      title: const Text('조 이동 / 등반',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              fontFamily: 'Pretendard',
              letterSpacing: -0.5)),
      description: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        child: Text(
          '${widget.memberFullName} 성도님을\n어느 조로 이동하시겠습니까?',
          style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSub,
              height: 1.5,
              fontFamily: 'Pretendard'),
        ),
      ),
      actionsAxis: Axis.horizontal,
      expandActionsWhenTiny: false,
      removeBorderRadiusWhenTiny: false,
      titleTextAlign: TextAlign.start,
      descriptionTextAlign: TextAlign.start,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.9,
        minWidth: 320,
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이동할 조 선택',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSub,
                    fontFamily: 'Pretendard',
                    letterSpacing: -0.2)),
            const SizedBox(height: 10),
            groupsAsync.when(
              data: (groups) {
                final options = groups
                    .where((g) => g['name'] != widget.currentGroupName)
                    .toList();
                final filteredOptions = _groupSearchQuery.isEmpty
                    ? options
                    : options
                        .where((g) => (g['name'] as String)
                            .toLowerCase()
                            .contains(_groupSearchQuery.toLowerCase()))
                        .toList();

                if (options.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('이동 가능한 다른 조가 없습니다.',
                          style: TextStyle(color: AppTheme.textSub)),
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return ShadSelect<String>.withSearch(
                      placeholder: const Text('조를 선택해주세요',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSub,
                              fontFamily: 'Pretendard')),
                      initialValue: _selectedGroupId,
                      minWidth: constraints.maxWidth,
                      maxHeight: 300,
                      decoration: ShadDecoration(
                        color: Colors.white,
                        border: ShadBorder.all(
                          radius: BorderRadius.circular(12),
                          width: 1,
                          color: AppTheme.border,
                        ),
                        shape: BoxShape.rectangle,
                      ),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedGroupId = val);
                      },
                      selectedOptionBuilder: (context, value) {
                        final group = options.firstWhere(
                            (g) => g['id'] == value,
                            orElse: () => options.first);
                        return Text(group['name'] as String,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMain,
                                fontFamily: 'Pretendard'));
                      },
                      options: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: Text('조 목록',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSub,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Pretendard')),
                        ),
                        ...filteredOptions.map((g) => ShadOption(
                              value: g['id'] as String,
                              child: Text(g['name'] as String,
                                  style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14)),
                            )),
                      ],
                      searchPlaceholder: const Text('조 이름 검색',
                          style: TextStyle(
                              fontFamily: 'Pretendard', fontSize: 14)),
                      onSearchChanged: (query) =>
                          setState(() => _groupSearchQuery = query),
                    );
                  },
                );
              },
              loading: () => Center(child: ShadcnSpinner()),
              error: (e, _) => Text('조 목록 로딩 실패: $e'),
            ),
          ],
        ),
      ),
      actions: [
        ShadButton.ghost(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('취소',
              style:
                  TextStyle(color: AppTheme.textSub, fontFamily: 'Pretendard')),
        ),
        ShadButton(
          onPressed: _isSaving || _selectedGroupId == null ? null : _save,
          child: _isSaving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('이동 완료',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final repo = ref.read(repositoryProvider);

      // 1. 프로필 연결 여부 확인
      final memberRes = await Supabase.instance.client
          .from('member_directory')
          .select('profile_id, full_name, church_id')
          .eq('id', widget.directoryMemberId)
          .single();

      final String? profileId = memberRes['profile_id'];
      final String churchId = memberRes['church_id'];

      if (profileId != null) {
        // 2-A. 프로필이 있는 경우: completeOnboarding 등으로 전체 업데이트
        await repo.completeOnboarding(
          profileId: profileId,
          fullName: memberRes['full_name'],
          churchId: churchId,
          groupId: _selectedGroupId,
        );
      }

      // 2-B. Directory 정보 업데이트
      final groups =
          await ref.read(departmentGroupsProvider(widget.departmentId).future);
      final targetGroup = groups.firstWhere((g) => g['id'] == _selectedGroupId);

      await repo.updateDirectoryMember(widget.directoryMemberId, {
        'group_name': targetGroup['name'],
      });

      // Refresh providers — invalidate both old and new group member lists
      ref.invalidate(departmentGroupsProvider(widget.departmentId));
      ref.invalidate(groupMembersProvider(widget.currentGroupId));
      ref.invalidate(groupMembersProvider(_selectedGroupId!));
      if (profileId != null) ref.invalidate(userProfileProvider);

      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pop(context); // Go back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${targetGroup['name']}로 이동되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업데이트 중 오류가 발생했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
