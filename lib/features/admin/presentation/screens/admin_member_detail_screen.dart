import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AdminMemberDetailScreen extends ConsumerStatefulWidget {
  final String directoryMemberId;
  final String fullName;
  final String groupName;

  const AdminMemberDetailScreen({
    super.key,
    required this.directoryMemberId,
    required this.fullName,
    required this.groupName,
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
}
