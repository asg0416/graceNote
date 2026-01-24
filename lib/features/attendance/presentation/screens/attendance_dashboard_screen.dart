import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/features/attendance/presentation/screens/attendance_prayer_screen.dart';

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
        title: const Text('출석 관리 대시보드', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 20)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (isLoading || historyAsync.isRefreshing)
            const SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryIndigo),
              ),
            ),
          Expanded(
            child: (history.isEmpty && isLoading)
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryIndigo))
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryHeader(history, isLoading: isLoading),
                        _buildGraphSection(history, isLoading: isLoading),
                        _buildHistoryList(history, isLoading: isLoading),
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
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.groupName, style: const TextStyle(color: AppTheme.primaryIndigo, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('우리 조 출석 요약', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryItem('선택 주차', activeWeek['week_id'] != null ? '${activeWeek['present_count']}명 / ${activeWeek['total_count']}' : '-', Colors.blue),
                _buildSummaryItem('평균 출석', history.isNotEmpty ? '${(history.map((e) => e['present_count'] as int).reduce((a, b) => a + b) / history.length).toStringAsFixed(1)}명' : '-', Colors.indigo),
                _buildSummaryItem('기록 주차', '${history.length}회', Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSub, fontSize: 12)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
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
    final reversedHistory = history.reversed.toList();
    
    return Container(
      height: 280, // Height increased for arrows and labels
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
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
                      icon: const Icon(Icons.arrow_back_ios_new, size: 16, color: AppTheme.primaryIndigo),
                      onPressed: _previousMonth,
                      tooltip: '이전 달',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.primaryIndigo),
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
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryIndigo),
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
                maxY: (history.isEmpty ? 10 : (history.map((e) => e['total_count'] as int).reduce((a, b) => a > b ? a : b) + 4)).toDouble(),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchCallback: (event, response) {
                    if (response != null && response.spot != null && event is FlTapUpEvent) {
                      setState(() {
                        _selectedWeekId = reversedHistory[response.spot!.touchedBarGroupIndex]['week_id'];
                      });
                    }
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Colors.transparent,
                    tooltipPadding: EdgeInsets.zero,
                    tooltipMargin: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        rod.toY.toInt().toString(),
                        const TextStyle(
                          color: AppTheme.primaryIndigo,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                  handleBuiltInTouches: true,
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
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('${date.month}/${date.day}', style: const TextStyle(fontSize: 10, color: AppTheme.textSub)),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: AppTheme.textSub)),
                      reservedSize: 28,
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5),
                borderData: FlBorderData(show: false),
                barGroups: reversedHistory.asMap().entries.map((e) {
                  final attendance = (e.value['present_count'] as int).toDouble();
                  final total = (e.value['total_count'] as int).toDouble();
                  final isSelected = _selectedWeekId == e.value['week_id'] || (_selectedWeekId == null && e.key == reversedHistory.length - 1);

                  return BarChartGroupData(
                    x: e.key,
                    showingTooltipIndicators: [0],
                    barRods: [
                      BarChartRodData(
                        toY: attendance,
                        color: isSelected ? AppTheme.primaryIndigo : AppTheme.primaryIndigo.withOpacity(0.4),
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(6)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: total,
                          color: AppTheme.divider.withOpacity(isSelected ? 0.35 : 0.15),
                        ),
                      ),
                    ],
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
          padding: EdgeInsets.fromLTRB(24, 32, 24, 16),
          child: Text('이 달의 주차별 기록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
        ),
        SizedBox(
          height: 100,
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
                  width: 100,
                  margin: const EdgeInsets.only(right: 12, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryIndigo : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSelected ? AppTheme.primaryIndigo : AppTheme.divider),
                    boxShadow: [
                      if (isSelected) BoxShadow(color: AppTheme.primaryIndigo.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(DateFormat('M/d').format(date), 
                        style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppTheme.textMain)),
                      const SizedBox(height: 4),
                      Text('${item['present_count']}명', 
                        style: TextStyle(fontSize: 12, color: isSelected ? Colors.white.withOpacity(0.8) : AppTheme.textSub)),
                    ],
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

              return Container(
                width: double.infinity, // 가로 전체를 차지하도록 수정
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.divider.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attendanceList.map((att) {
                      final member = att['member_directory'];
                      if (member == null) return const SizedBox.shrink();
                      
                      final status = att['status'];
                      final isPresent = status == 'present' || status == 'late';
                      final color = status == 'present' ? Colors.green : (status == 'late' ? Colors.orange : Colors.grey.withOpacity(0.3));
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: color.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(member['full_name'], 
                              style: TextStyle(
                                fontSize: 12, 
                                fontWeight: isPresent ? FontWeight.bold : FontWeight.normal,
                                color: isPresent ? color : AppTheme.textSub,
                              )
                            ),
                            if (status == 'late')
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text('지각', style: TextStyle(fontSize: 8, color: Colors.orange, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
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
