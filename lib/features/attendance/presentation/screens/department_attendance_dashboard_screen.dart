import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

class DepartmentAttendanceDashboardScreen extends ConsumerStatefulWidget {
  final String departmentId;
  final String departmentName;

  const DepartmentAttendanceDashboardScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  ConsumerState<DepartmentAttendanceDashboardScreen> createState() => _DepartmentAttendanceDashboardScreenState();
}

class _DepartmentAttendanceDashboardScreenState extends ConsumerState<DepartmentAttendanceDashboardScreen> {
  String? _selectedWeekId;
  late int _viewYear;
  late int _viewMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewYear = now.year;
    _viewMonth = now.month;
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

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(departmentAttendanceHistoryProvider('${widget.departmentId}:$_viewYear:$_viewMonth'));
    final history = historyAsync.value ?? [];
    final isLoading = historyAsync.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('부서 출석 통계', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18, fontFamily: 'Pretendard')),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(lucide.LucideIcons.chevronLeft, color: AppTheme.textMain, size: 24),
        ),
      ),
      body: Column(
        children: [
          if (isLoading)
            const SizedBox(height: 2, child: LinearProgressIndicator(backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet))),
          Expanded(
            child: (history.isEmpty && isLoading)
                ? Center(child: ShadcnSpinner())
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        if (history.isNotEmpty) _buildSummaryHeader(_selectedWeekId != null ? history.firstWhere((h) => h['week_id'] == _selectedWeekId, orElse: () => history.first) : history.first),
                        _buildHistoryList(history, isLoading: isLoading),
                        _buildGraphSection(history, isLoading: isLoading),
                        if (history.isNotEmpty) _buildDetailedAttendanceSection(_selectedWeekId ?? history.first['week_id'], isLoading: isLoading),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(Map<String, dynamic> weekData) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border.withOpacity(0.5), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1))),
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
                      Text('${widget.departmentName} 출석 요약', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'Pretendard', letterSpacing: -0.5)),
                    ],
                  ),
                  const SizedBox(height: 24),
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
                        _buildSummaryItem('출석 인원', '${weekData['present_count']}명', lucide.LucideIcons.calendarCheck2),
                        Container(width: 1, height: 30, color: Colors.white.withOpacity(0.2)),
                        _buildSummaryItem('전체 구성원', '${weekData['total_count']}명', lucide.LucideIcons.users),
                        Container(width: 1, height: 30, color: Colors.white.withOpacity(0.2)),
                        _buildSummaryItem('출석률', '${(weekData['attendance_rate'] * 100).toInt()}%', lucide.LucideIcons.trendingUp),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 16),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, fontFamily: 'Pretendard')),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w500, fontFamily: 'Pretendard')),
      ],
    );
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> history, {bool isLoading = false}) {
    if (history.isEmpty && !isLoading) return const SizedBox.shrink();
    final reversedHistory = history.reversed.toList();
    return Opacity(
      opacity: isLoading ? 0.6 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(26, 24, 24, 12),
            child: Text('주차별 기록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
          ),
          SizedBox(
            height: 48,
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
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryViolet : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? AppTheme.primaryViolet : AppTheme.border),
                    ),
                    child: Center(
                      child: Text(DateFormat('M/d').format(date), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : AppTheme.textSub, fontFamily: 'Pretendard')),
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

  Widget _buildGraphSection(List<Map<String, dynamic>> history, {bool isLoading = false}) {
    final reversedHistory = history.reversed.toList();
    return Container(
      height: 280,
      padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.border.withOpacity(0.5))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_viewYear년 $_viewMonth월 추이', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textMain)),
                Row(
                  children: [
                    IconButton(icon: const Icon(lucide.LucideIcons.chevronLeft, size: 18), onPressed: _previousMonth),
                    IconButton(icon: const Icon(lucide.LucideIcons.chevronRight, size: 18), onPressed: (_viewYear == DateTime.now().year && _viewMonth == DateTime.now().month) ? null : _nextMonth),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (history.isEmpty)
            const Expanded(child: Center(child: Text('기록이 없습니다.', style: TextStyle(color: AppTheme.textSub))))
          else
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (history.map((e) => e['total_count'] as int).reduce((a, b) => a > b ? a : b) + 5).toDouble(),
                  barTouchData: BarTouchData(
                    touchCallback: (event, response) {
                      if (event is FlTapUpEvent && response != null && response.spot != null) {
                        final index = response.spot!.touchedBarGroupIndex;
                        if (index >= 0 && index < reversedHistory.length) {
                          setState(() {
                            _selectedWeekId = reversedHistory[index]['week_id'];
                          });
                        }
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
                            color: AppTheme.primaryViolet,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: reversedHistory.asMap().entries.map((e) {
                    final isSelected = _selectedWeekId == e.value['week_id'] || (_selectedWeekId == null && e.key == reversedHistory.length - 1);
                    return BarChartGroupData(
                      x: e.key,
                      showingTooltipIndicators: [0],
                      barRods: [
                        BarChartRodData(
                          toY: (e.value['present_count'] as int).toDouble(),
                          color: isSelected ? AppTheme.primaryViolet : AppTheme.primaryViolet.withOpacity(0.4),
                          width: 14,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          backDrawRodData: BackgroundBarChartRodData(show: true, toY: (e.value['total_count'] as int).toDouble(), color: const Color(0xFFF1F5F9)),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= reversedHistory.length) return const SizedBox.shrink();
                      final date = DateTime.parse(reversedHistory[idx]['week_date']);
                      return Padding(padding: const EdgeInsets.only(top: 8), child: Text('${date.month}/${date.day}', style: const TextStyle(fontSize: 10, color: AppTheme.textSub)));
                    })),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: AppTheme.textSub)))),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: const Color(0xFFCBD5E1), // [FIX] 더 진한 회색 (Slate-300)
                      strokeWidth: 1.0,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailedAttendanceSection(String weekId, {bool isLoading = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 20, 24, 16),
          child: Text('조별 상세 현황', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
        ),
        ref.watch(departmentWeeklyAttendanceProvider('${widget.departmentId}:$weekId')).when(
          data: (data) {
            final groups = List<Map<String, dynamic>>.from(data['groups']);
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: groups.length,
              itemBuilder: (context, index) => _GroupAttendanceAccordion(group: groups[index]),
            );
          },
          loading: () => Center(child: ShadcnSpinner()),
          error: (e, s) => Center(child: Text('로딩 실패: $e')),
        ),
      ],
    );
  }
}

class _GroupAttendanceAccordion extends StatefulWidget {
  final Map<String, dynamic> group;
  const _GroupAttendanceAccordion({required this.group});
  @override
  State<_GroupAttendanceAccordion> createState() => _GroupAttendanceAccordionState();
}

class _GroupAttendanceAccordionState extends State<_GroupAttendanceAccordion> {
  bool _isExpanded = false;

  Color _getRateColor(int rate) {
    if (rate >= 80) return const Color(0xFF10B981);
    if (rate >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final members = List<Map<String, dynamic>>.from(group['members']);
    final presentCount = group['present_count'];
    final totalCount = group['total_count'];
    final rate = totalCount > 0 ? (presentCount / totalCount * 100).toInt() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isExpanded ? AppTheme.primaryViolet.withOpacity(0.3) : AppTheme.divider, width: _isExpanded ? 1.5 : 1.0),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            title: Text(group['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            subtitle: Text('출석 $presentCount명 / 총 $totalCount명', style: const TextStyle(fontSize: 12, color: AppTheme.textSub)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _getRateColor(rate).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('$rate%', style: TextStyle(color: _getRateColor(rate), fontWeight: FontWeight.w900, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Icon(_isExpanded ? lucide.LucideIcons.chevronUp : lucide.LucideIcons.chevronDown, size: 18),
              ],
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  children: members.map((m) {
                    final isPresent = m['status'] == 'present' || m['status'] == 'late';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: isPresent ? AppTheme.accentViolet : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isPresent ? AppTheme.primaryViolet.withOpacity(0.3) : AppTheme.border)),
                      child: Text(m['full_name'], style: TextStyle(fontSize: 12, fontWeight: isPresent ? FontWeight.w800 : FontWeight.w600, color: isPresent ? AppTheme.primaryViolet : AppTheme.textSub)),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
