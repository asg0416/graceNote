import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/features/attendance/presentation/screens/attendance_prayer_screen.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

class AttendanceDashboardScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const AttendanceDashboardScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<AttendanceDashboardScreen> createState() => _AttendanceDashboardScreenState();
}

class _AttendanceDashboardScreenState extends ConsumerState<AttendanceDashboardScreen> {
  String? _selectedWeekId;
  late int _viewYear;
  late int _viewMonth;
  List<Map<String, dynamic>>? _cachedHistory;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewYear = now.year;
    _viewMonth = now.month;
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(attendanceHistoryProvider('${widget.groupId}:$_viewYear:$_viewMonth'));
    
    // 데이터가 있을 때만 캐시 업데이트
    if (historyAsync.hasValue) {
      _cachedHistory = historyAsync.value;
    }

    final history = _cachedHistory ?? [];
    final isLoading = historyAsync.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('출석 통계', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18, fontFamily: 'Pretendard')),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: const [],
      ),
      body: Column(
        children: [
          if (isLoading || historyAsync.isRefreshing)
            const SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet),
              ),
            ),
          Expanded(
            child: (history.isEmpty && isLoading)
                ? Center(child: ShadcnSpinner(color: AppTheme.primaryViolet))
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryHeader(history, isLoading: isLoading),
                        _buildHistoryList(history, isLoading: isLoading), // [MOVE] 상단(요약 아래)으로 이동
                        _buildGraphSection(history, isLoading: isLoading),
                        if (_selectedWeekId != null || (history.isNotEmpty))
                          _buildDetailedAttendanceSection(_selectedWeekId ?? history.first['week_id'], isLoading: isLoading),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bar_chart_rounded, size: 80, color: AppTheme.divider),
          const SizedBox(height: 16),
          const Text('아직 출석 기록이 없습니다.', style: TextStyle(color: AppTheme.textSub, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AttendancePrayerScreen()),
              );
            },
            child: const Text('첫 출석 기록하기'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(List<Map<String, dynamic>> history, {bool isLoading = false}) {
    final activeWeekId = _selectedWeekId ?? (history.isNotEmpty ? history.first['week_id'] : null);
    final activeWeek = (history.isNotEmpty) 
        ? history.firstWhere((h) => h['week_id'] == activeWeekId, orElse: () => history.first)
        : {'present_count': 0, 'total_count': 0, 'week_id': null, 'week_date': ''};

    return Opacity(
      opacity: isLoading ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8B5CF6), // 진한 보라
              Color(0xFF6366F1), // 인디고 계열
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border.withOpacity(0.5), width: 1.0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // [STYLE] 배경 데코레이션 (추상적인 원형 패턴)
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(lucide.LucideIcons.barChart3, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          '우리 조 출석 요약',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontFamily: 'Pretendard',
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // [STYLE] 글래스모피즘 카드 레이아웃
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryItem(
                            '선택 주차', 
                            activeWeek['week_id'] != null ? '${activeWeek['present_count']}명' : '-', 
                            lucide.LucideIcons.calendarCheck2,
                          ),
                          Container(width: 1, height: 30, color: Colors.white.withOpacity(0.2)),
                          _buildSummaryItem(
                            '평균 출석', 
                            history.isNotEmpty ? '${(history.map((e) => e['present_count'] as int).reduce((a, b) => a + b) / history.length).toStringAsFixed(1)}명' : '-', 
                            lucide.LucideIcons.users,
                          ),
                          Container(width: 1, height: 30, color: Colors.white.withOpacity(0.2)),
                          _buildSummaryItem(
                            '기록 주차', 
                            '${history.length}회', 
                            lucide.LucideIcons.history,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 16),
        const SizedBox(height: 6),
        Text(
          label, 
          style: TextStyle(
            color: Colors.white.withOpacity(0.7), 
            fontSize: 11, 
            fontWeight: FontWeight.w600, 
            fontFamily: 'Pretendard',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value, 
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 16, 
            fontWeight: FontWeight.w900, 
            fontFamily: 'Pretendard', 
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  void _previousMonth() {
    setState(() {
      if (_viewMonth == 1) {
        _viewYear--;
        _viewMonth = 12;
      } else {
        _viewMonth--;
      }
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_viewYear == now.year && _viewMonth == now.month) return;

    setState(() {
      if (_viewMonth == 12) {
        _viewYear++;
        _viewMonth = 1;
      } else {
        _viewMonth++;
      }
    });
  }

  Widget _buildGraphSection(List<Map<String, dynamic>> history, {bool isLoading = false}) {
    // Reverse to show chronological order in graph
    // Reverse to show chronological order in graph
    final reversedHistory = history.reversed.toList();
    
    // [FIX] 배경 막대 가시성: 데이터 중 최대 인원수를 배경 높이로 설정하여 비어있는 주차도 가시성 확보
    double maxAttendance = 10;
    if (history.isNotEmpty) {
      final actualMax = history.map((e) => (e['total_count'] as int)).reduce((a, b) => a > b ? a : b).toDouble();
      maxAttendance = actualMax > 0 ? actualMax : 10;
    }

    return Container(
      height: 280, // Height increased for arrows and labels
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border, width: 1.0), // [STYLE] 그림자 제거 후 테두리 복원
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_viewYear년 $_viewMonth월 출석 (명)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSub)),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(lucide.LucideIcons.chevronLeft, size: 18, color: AppTheme.textSub),
                      onPressed: _previousMonth,
                      tooltip: '이전 달',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(lucide.LucideIcons.chevronRight, size: 18, color: AppTheme.textSub),
                      onPressed: (_viewYear == DateTime.now().year && _viewMonth == DateTime.now().month) ? null : _nextMonth,
                      tooltip: '다음 달',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isLoading)
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: ShadcnSpinner(color: AppTheme.primaryViolet),
                ),
              ),
            )
          else if (history.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.event_busy_rounded, size: 40, color: AppTheme.divider),
                    const SizedBox(height: 8),
                    const Text('이 달의 출석 기록이 없습니다.', style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: BarChart(
                BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAttendance + 4, // [FIX] 계산된 최대치 기반 (명시적 표시를 위해 여유분 확보)
                barTouchData: BarTouchData(
                  enabled: true,
                  touchCallback: (event, response) {
                    if (response != null && response.spot != null && event is FlTapUpEvent) {
                      final index = response.spot!.touchedBarGroupIndex;
                      if (index >= 0 && index < reversedHistory.length) {
                        setState(() {
                          _selectedWeekId = reversedHistory[index]['week_id'];
                        });
                      }
                    }
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Colors.transparent, // 배경 투명
                    tooltipPadding: EdgeInsets.zero,
                    tooltipMargin: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()}명',
                        const TextStyle(
                          color: AppTheme.primaryViolet,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          fontFamily: 'Pretendard',
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        int idx = value.toInt();
                        if (idx < 0 || idx >= reversedHistory.length) return const SizedBox.shrink();
                        final date = DateTime.parse(reversedHistory[idx]['week_date']);
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text('${date.month}/${date.day}', style: const TextStyle(fontSize: 11, color: AppTheme.textSub, fontWeight: FontWeight.w500)),
                        );
                      },
                      reservedSize: 32,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 11, color: AppTheme.textSub)),
                      reservedSize: 28,
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true, 
                  drawVerticalLine: false, 
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[300]!, strokeWidth: 1), // [STYLE] 그리드 선명도 개선
                ),
                borderData: FlBorderData(show: false),
                barGroups: reversedHistory.asMap().entries.map((e) {
                  final attendance = (e.value['present_count'] as int).toDouble();
                  final total = (e.value['total_count'] as int).toDouble();
                  final isSelected = _selectedWeekId == e.value['week_id'] || (_selectedWeekId == null && e.key == reversedHistory.length - 1);

                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: attendance,
                        color: isSelected ? AppTheme.primaryViolet : AppTheme.primaryViolet.withOpacity(0.3),
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxAttendance, // [FIX] 모든 막대의 배경 높이를 통일하여 가시성 확보
                          color: const Color(0xFFF1F5F9),
                        ),
                      ),
                    ],
                    showingTooltipIndicators: [0],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> history, {bool isLoading = false}) {
    if (history.isEmpty && !isLoading) return const SizedBox.shrink();

    // Reverse to match chronological order of the graph (oldest left, newest right)
    final reversedHistory = history.reversed.toList();

    return Opacity(
      opacity: isLoading ? 0.6 : 1.0,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 24, 24, 12), // [LAYOUT] 간격 미세 조정
          child: Text('주차별 기록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
        ),
        SizedBox(
          height: 48, // [STYLE] 높이 감소
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: reversedHistory.length,
            itemBuilder: (context, index) {
              final item = reversedHistory[index];
              final date = DateTime.parse(item['week_date']);
              final isSelected = _selectedWeekId == item['week_id'] || (_selectedWeekId == null && index == reversedHistory.length - 1);
 
              return GestureDetector(
                onTap: () => setState(() => _selectedWeekId = item['week_id']),
                child: Container(
                  margin: const EdgeInsets.only(right: 8, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0), // [STYLE] 좌우 넓히고 상하 패딩 제거
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryViolet : const Color(0xFFF1F5F9), // [STYLE] 미선택 시 연한 회색 배경
                    borderRadius: BorderRadius.circular(10), // [STYLE] 더 샤프한 뱃지 느낌
                    border: Border.all(color: isSelected ? AppTheme.primaryViolet : AppTheme.border), // [STYLE] 테두리 복원
                  ),
                  child: Center(
                    child: Text(
                      DateFormat('M/d').format(date), 
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700, 
                        color: isSelected ? Colors.white : AppTheme.textSub,
                        fontFamily: 'Pretendard',
                      )
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildDetailedAttendanceSection(String weekId, {bool isLoading = false}) {
    final groupsAsync = ref.watch(userGroupsProvider);
    final churchId = groupsAsync.value?.first['church_id'] ?? '';
    
    return Opacity(
      opacity: isLoading ? 0.5 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 32, 24, 16),
            child: Text('상세 현황 (누가 오고 안왔는지)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
          ),
          ref.watch(weeklyDataProvider('${widget.groupId}:$churchId:$weekId')).when(
            data: (data) {
              final attendanceList = List<Map<String, dynamic>>.from(data['attendance']);
              if (attendanceList.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('데이터가 없습니다.')));

              // [SORT] 명단 정렬 (부부별)
              attendanceList.sort((a, b) {
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

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.border, width: 1.0), // [STYLE] 테두리 복원
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Wrap(
                        spacing: 6, // [STYLE] 간격 좁힘
                        runSpacing: 8,
                        children: attendanceList.map((att) {
                          final member = att['member_directory'];
                          if (member == null) return const SizedBox.shrink();
                          
                          final status = att['status'];
                          final isPresent = status == 'present' || status == 'late';
                          
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // [STYLE] 패딩 축소
                            decoration: BoxDecoration(
                              color: isPresent ? AppTheme.accentViolet : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12), // [STYLE] 조금 더 샤프한 어드민 스타일 뱃지
                              border: Border.all(
                                color: isPresent ? AppTheme.primaryViolet.withOpacity(0.4) : AppTheme.border.withOpacity(0.6),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              member['full_name'], 
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isPresent ? FontWeight.w800 : FontWeight.w600,
                                color: isPresent ? AppTheme.primaryViolet : AppTheme.textSub,
                                fontFamily: 'Pretendard',
                                letterSpacing: -0.3,
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }
                  ),
                ),
              );
            },
            loading: () => Center(child: Padding(padding: EdgeInsets.all(40), child: ShadcnSpinner())),
            error: (e, s) => Center(child: Text('로딩 실패: $e')),
          ),
        ],
      ),
    );
  }

  Color _getRateColor(int rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 50) return Colors.orange;
    return Colors.red;
  }
}
