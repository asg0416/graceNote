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
  final String departmentId;

  const AdminMemberDetailScreen({
    super.key,
    required this.directoryMemberId,
    required this.fullName,
    required this.groupName,
    required this.departmentId,
  });

  @override
  ConsumerState<AdminMemberDetailScreen> createState() => _AdminMemberDetailScreenState();
}

class _AdminMemberDetailScreenState extends ConsumerState<AdminMemberDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _history = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 15;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
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
        pageSize: _pageSize
      );

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Slightly off-white bg for cards to pop
      appBar: AppBar(
        title: const Text('구성원 상세 정보', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(color: Colors.white, child: _buildProfileCard()),
            
            // [NEW] 등반/조 이동 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showMoveGroupDialog(),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('조 이동 / 등반 처리'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryViolet,
                    side: const BorderSide(color: AppTheme.primaryViolet),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: const Text('기도제목 히스토리', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
            ),

            if (_history.isEmpty && !_isLoading && _error == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('등록된 기도제목이 없습니다.', style: TextStyle(color: AppTheme.textSub)),
                ),
              ),
            
            if (_error != null)
              Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('로딩 에러: $_error'))),

            ..._buildGroupedHistory(),

            if (_isLoading)
               Padding(padding: const EdgeInsets.all(20), child: Center(child: ShadcnSpinner())),
               
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
      final dateStr = weeksData != null ? weeksData['week_date'] : prayer['created_at'];
      final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
      
      final currentYearMonth = DateFormat('yyyy.MM').format(date);
      
      if (lastYearMonth != currentYearMonth) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryViolet.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat('yyyy년 M월').format(date),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryViolet, fontSize: 13),
                  ),
                ),
                const Expanded(child: Divider(indent: 12, color: AppTheme.border)),
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
              widget.fullName.length >= 2 ? widget.fullName.substring(widget.fullName.length - 2) : widget.fullName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryViolet),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(widget.groupName, style: const TextStyle(fontSize: 15, color: AppTheme.textSub, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
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
                 Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.primaryViolet),
                 SizedBox(width: 6),
                 Text(
                   dateDisplay, 
                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textMain)
                 ),
               ],
             ),
             const SizedBox(height: 12),
             if (title.isNotEmpty) ...[
               Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
               const SizedBox(height: 6),
             ],
             Text(
               content,
               style: const TextStyle(color: AppTheme.textSub, fontSize: 15, height: 1.6),
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
        currentGroupName: widget.groupName,
        directoryMemberId: widget.directoryMemberId,
        memberFullName: widget.fullName,
      ),
    );
  }
}

class _MoveGroupDialog extends ConsumerStatefulWidget {
  final String departmentId;
  final String currentGroupName;
  final String directoryMemberId;
  final String memberFullName;

  const _MoveGroupDialog({
    super.key,
    required this.departmentId,
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

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(departmentGroupsProvider(widget.departmentId));

    return AlertDialog(
      title: const Text('조 이동 / 등반', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.memberFullName} 성도님을 어느 조로 이동하시겠습니까?', style: const TextStyle(fontSize: 14, color: AppTheme.textSub)),
            const SizedBox(height: 20),
            groupsAsync.when(
              data: (groups) {
                // 현재 조 제외하고 옵션 제공
                final options = groups.where((g) => g['name'] != widget.currentGroupName).toList();
                
                if (options.isEmpty) {
                  return const Text('이동 가능한 다른 조가 없습니다.');
                }

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: '이동할 조 선택',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  value: _selectedGroupId,
                  items: options.map((g) => DropdownMenuItem(
                    value: g['id'] as String,
                    child: Text(g['name'] as String),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedGroupId = val),
                  hint: const Text('조를 선택해주세요'),
                );
              },
              loading: () => const Center(child: ShadcnSpinner()),
              error: (e, _) => Text('조 목록 로딩 실패: $e'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: AppTheme.textSub)),
        ),
        TextButton(
          onPressed: _isSaving || _selectedGroupId == null ? null : _save,
          child: _isSaving 
            ? const SizedBox(width: 16, height: 16, child: ShadcnSpinner()) 
            : const Text('이동 / 등반 완료', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryViolet)),
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
      final groups = await ref.read(departmentGroupsProvider(widget.departmentId).future);
      final targetGroup = groups.firstWhere((g) => g['id'] == _selectedGroupId);
      
      await repo.updateDirectoryMember(widget.directoryMemberId, {
        'group_name': targetGroup['name'],
      });

      // Refresh providers
      ref.invalidate(departmentGroupsProvider(widget.departmentId));
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
