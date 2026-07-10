import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:grace_note/core/utils/attendance_summary.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:grace_note/core/widgets/season_context_chip.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

class DepartmentAttendanceDashboardScreen extends ConsumerStatefulWidget {
  final String departmentId;
  final String departmentName;
  final bool isCoupleMode;

  const DepartmentAttendanceDashboardScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
    this.isCoupleMode = false,
  });

  @override
  ConsumerState<DepartmentAttendanceDashboardScreen> createState() =>
      _DepartmentAttendanceDashboardScreenState();
}

class _DepartmentAttendanceDashboardScreenState
    extends ConsumerState<DepartmentAttendanceDashboardScreen> {
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
    final historyAsync = ref.watch(departmentAttendanceHistoryProvider(
        '${widget.departmentId}:$_viewYear:$_viewMonth'));
    final history = historyAsync.value ?? [];
    final isLoading = historyAsync.isLoading;

    final noMeetingListAsync = widget.departmentId.isNotEmpty
        ? ref.watch(noMeetingDaysInMonthProvider(
            '${widget.departmentId}:$_viewYear:$_viewMonth'))
        : const AsyncValue<List<NoMeetingDayModel>>.data([]);
    final noMeetingList = noMeetingListAsync.value ?? [];
    final noMeetingDates = <String>{
      for (final d in noMeetingList)
        '${d.weekDate.year}-${d.weekDate.month.toString().padLeft(2, '0')}-${d.weekDate.day.toString().padLeft(2, '0')}'
    };
    final activeWeek = history.isNotEmpty
        ? history.firstWhere(
            (h) =>
                h['week_id'] == (_selectedWeekId ?? history.first['week_id']),
            orElse: () => history.first,
          )
        : null;
    final activeWeekDate = activeWeek == null
        ? null
        : DateTime.tryParse(activeWeek['week_date']?.toString() ?? '');

    // [FIX] 에러 발생 시 사용자에게 노출하지 않고 3초 후 자동 재시도
    if (historyAsync.hasError && !historyAsync.isLoading) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          ref.invalidate(departmentAttendanceHistoryProvider(
              '${widget.departmentId}:$_viewYear:$_viewMonth'));
        }
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('부서 출석 통계',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
                fontSize: 18,
                fontFamily: 'Pretendard')),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (activeWeekDate != null && widget.departmentId.isNotEmpty)
            SeasonContextChip(
              departmentId: widget.departmentId,
              weekDate: activeWeekDate,
              iconOnly: true,
              margin: const EdgeInsets.only(right: 12),
            ),
        ],
      ),
      body: Column(
        children: [
          if (isLoading)
            const SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet))),
          Expanded(
            // [FIX] 최초 로딩 시에만 스피너, 그 외에는 항상 전체 UI 표시하여 이전 달 접근 가능
            child: (history.isEmpty &&
                    historyAsync.isLoading &&
                    !historyAsync.hasValue)
                ? Center(child: ShadcnSpinner())
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(departmentAttendanceHistoryProvider(
                          '${widget.departmentId}:$_viewYear:$_viewMonth'));
                      if (_selectedWeekId != null) {
                        ref.invalidate(departmentWeeklyAttendanceProvider(
                            '${widget.departmentId}:$_selectedWeekId'));
                      } else if (history.isNotEmpty) {
                        ref.invalidate(departmentWeeklyAttendanceProvider(
                            '${widget.departmentId}:${history.first['week_id']}'));
                      }
                      await ref.read(departmentAttendanceHistoryProvider(
                              '${widget.departmentId}:$_viewYear:$_viewMonth')
                          .future);
                    },
                    color: AppTheme.primaryViolet,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      child: Column(
                        children: [
                          history.isNotEmpty
                              ? _buildSummaryHeader(
                                  _selectedWeekId ?? history.first['week_id'],
                                  noMeetingDates: noMeetingDates,
                                  noMeetingList: noMeetingList)
                              : _buildEmptySummaryHeader(),
                          _buildHistoryList(history, isLoading: isLoading),
                          _buildGraphSection(history, isLoading: isLoading),
                          if (history.isNotEmpty) ...[
                            () {
                              final activeWeekId =
                                  _selectedWeekId ?? history.first['week_id'];
                              final activeWeek = history.firstWhere(
                                (h) => h['week_id'] == activeWeekId,
                                orElse: () => history.first,
                              );
                              final activeWeekDate =
                                  activeWeek['week_date'] as String? ?? '';
                              if (!noMeetingDates.contains(activeWeekDate)) {
                                return _buildDetailedAttendanceSection(
                                    activeWeekId,
                                    isLoading: isLoading);
                              }
                              return const SizedBox.shrink();
                            }(),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(String weekId,
      {Set<String> noMeetingDates = const {},
      List<NoMeetingDayModel> noMeetingList = const []}) {
    final weeklyDataAsync = ref.watch(
        departmentWeeklyAttendanceProvider('${widget.departmentId}:$weekId'));

    // weekId에 해당하는 week_date 찾기 (noMeeting 판단용)
    // departmentAttendanceHistoryProvider에서 이미 history를 가지고 있으므로
    // weekId로 week_date를 추출할 수 있도록 history를 직접 읽음
    final historyAsync = ref.watch(departmentAttendanceHistoryProvider(
        '${widget.departmentId}:$_viewYear:$_viewMonth'));
    final history = historyAsync.value ?? [];
    final activeWeek = history.isNotEmpty
        ? history.firstWhere((h) => h['week_id'] == weekId,
            orElse: () => history.first)
        : <String, dynamic>{};
    final activeWeekDate = activeWeek['week_date'] as String? ?? '';
    final isNoMeeting = noMeetingDates.contains(activeWeekDate);
    final noMeetingReason = isNoMeeting && noMeetingList.isNotEmpty
        ? noMeetingList
            .firstWhere(
              (d) =>
                  '${d.weekDate.year}-${d.weekDate.month.toString().padLeft(2, '0')}-${d.weekDate.day.toString().padLeft(2, '0')}' ==
                  activeWeekDate,
              orElse: () => noMeetingList.first,
            )
            .reason
        : null;

    if (isNoMeeting) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF97316), Color(0xFFEA580C)],
          ),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: AppTheme.border.withOpacity(0.5), width: 1.0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1))),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(lucide.LucideIcons.barChart3,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text('${widget.departmentName} 출석 요약',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontFamily: 'Pretendard',
                                letterSpacing: -0.5)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.2), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('이번 주는 모임이 없습니다',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  fontFamily: 'Pretendard',
                                  letterSpacing: -0.5)),
                          if (noMeetingReason != null &&
                              noMeetingReason.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(noMeetingReason,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontFamily: 'Pretendard')),
                          ],
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

    return weeklyDataAsync.maybeWhen(
      skipLoadingOnRefresh: true,
      data: (data) {
        final groups = List<Map<String, dynamic>>.from(data['groups']);
        // [FIX] 멤버가 0명인 조는 출석 제출 자체가 불가능하므로 집계 모수에서 제외
        final validGroups =
            groups.where((g) => (g['total_count'] as num) > 0).toList();
        final totalGroups = validGroups.length;
        final submittedGroups =
            validGroups.where((g) => g['is_submitted'] == true).toList();
        final isAllSubmitted =
            totalGroups > 0 && submittedGroups.length == totalGroups;

        final summary = summarizeSubmittedDepartmentAttendance(submittedGroups);
        final totalPresent = summary.presentCount;
        final totalCount = summary.totalCount;
        final rate = summary.ratePercent;

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
            ),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: AppTheme.border.withOpacity(0.5), width: 1.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  top: -20,
                  child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1))),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(lucide.LucideIcons.barChart3,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('${widget.departmentName} 출석 요약',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  fontFamily: 'Pretendard',
                                  letterSpacing: -0.5)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.2), width: 1),
                        ),
                        child: isAllSubmitted
                            ? Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildSummaryItem('출석 인원', '${totalPresent}명',
                                      lucide.LucideIcons.calendarCheck2),
                                  Container(
                                      width: 1,
                                      height: 30,
                                      color: Colors.white.withOpacity(0.2)),
                                  _buildSummaryItem('전체 구성원', '${totalCount}명',
                                      lucide.LucideIcons.users),
                                  Container(
                                      width: 1,
                                      height: 30,
                                      color: Colors.white.withOpacity(0.2)),
                                  _buildSummaryItem('출석률', '$rate%',
                                      lucide.LucideIcons.trendingUp),
                                ],
                              )
                            : Column(
                                children: [
                                  const Text('아직 모든 조의 출석이 입력되지 않았습니다.',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('출석 입력 현황:',
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.8),
                                              fontSize: 13)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                            '${submittedGroups.length} / $totalGroups 조 완료',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14)),
                                      ),
                                    ],
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
        );
      },
      orElse: () => _buildSummaryHeaderSkeleton(),
    );
  }

  Widget _buildSummaryHeaderSkeleton() {
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
              child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1))),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4))),
                      const SizedBox(width: 8),
                      Container(
                          width: 140,
                          height: 18,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSkeletonSummaryItem(),
                        Container(
                            width: 1,
                            height: 30,
                            color: Colors.white.withOpacity(0.2)),
                        _buildSkeletonSummaryItem(),
                        Container(
                            width: 1,
                            height: 30,
                            color: Colors.white.withOpacity(0.2)),
                        _buildSkeletonSummaryItem(),
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

  Widget _buildSkeletonSummaryItem() {
    return Column(
      children: [
        Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3), shape: BoxShape.circle)),
        const SizedBox(height: 8),
        Container(
            width: 36,
            height: 14,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 4),
        Container(
            width: 48,
            height: 18,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4))),
      ],
    );
  }

  Widget _buildEmptySummaryHeader() {
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
              child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1))),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(lucide.LucideIcons.barChart3,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('${widget.departmentName} 출석 요약',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFamily: 'Pretendard',
                              letterSpacing: -0.5)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(
                            '출석 인원', '-', lucide.LucideIcons.calendarCheck2),
                        Container(
                            width: 1,
                            height: 30,
                            color: Colors.white.withOpacity(0.2)),
                        _buildSummaryItem(
                            '전체 구성원', '-', lucide.LucideIcons.users),
                        Container(
                            width: 1,
                            height: 30,
                            color: Colors.white.withOpacity(0.2)),
                        _buildSummaryItem(
                            '출석률', '-', lucide.LucideIcons.trendingUp),
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
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                fontFamily: 'Pretendard')),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                fontFamily: 'Pretendard')),
      ],
    );
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> history,
      {bool isLoading = false}) {
    if (history.isEmpty && !isLoading) return const SizedBox.shrink();
    final reversedHistory = history.reversed.toList();
    return Opacity(
      opacity: isLoading ? 0.6 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(26, 24, 24, 12),
            child: Text('주차별 기록',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMain)),
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
                final isSelected = _selectedWeekId == item['week_id'] ||
                    (_selectedWeekId == null &&
                        index == reversedHistory.length - 1);
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedWeekId = item['week_id']),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8, bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryViolet
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryViolet
                              : AppTheme.border),
                    ),
                    child: Center(
                      child: Text(DateFormat('M/d').format(date),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color:
                                  isSelected ? Colors.white : AppTheme.textSub,
                              fontFamily: 'Pretendard')),
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

  Widget _buildGraphSection(List<Map<String, dynamic>> history,
      {bool isLoading = false}) {
    final reversedHistory = history.reversed.toList();
    return Container(
      height: 280,
      padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border.withOpacity(0.5))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_viewYear년 $_viewMonth월 추이',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.textMain)),
                Row(
                  children: [
                    IconButton(
                        icon: const Icon(lucide.LucideIcons.chevronLeft,
                            size: 18),
                        onPressed: _previousMonth),
                    IconButton(
                        icon: const Icon(lucide.LucideIcons.chevronRight,
                            size: 18),
                        onPressed: (_viewYear == DateTime.now().year &&
                                _viewMonth == DateTime.now().month)
                            ? null
                            : _nextMonth),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (history.isEmpty)
            const Expanded(
                child: Center(
                    child: Text('기록이 없습니다.',
                        style: TextStyle(color: AppTheme.textSub))))
          else
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (history
                              .map((e) => e['total_count'] as int)
                              .reduce((a, b) => a > b ? a : b) +
                          5)
                      .toDouble(),
                  barTouchData: BarTouchData(
                    touchCallback: (event, response) {
                      if (event is FlTapUpEvent &&
                          response != null &&
                          response.spot != null) {
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
                        // [FIX] Index Safety Check
                        if (group.x.toInt() < 0 ||
                            group.x.toInt() >= reversedHistory.length) {
                          return null;
                        }

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
                    final isSelected = _selectedWeekId == e.value['week_id'] ||
                        (_selectedWeekId == null &&
                            e.key == reversedHistory.length - 1);
                    return BarChartGroupData(
                      x: e.key,
                      showingTooltipIndicators: [0],
                      barRods: [
                        BarChartRodData(
                          toY: (e.value['present_count'] as int).toDouble(),
                          color: isSelected
                              ? AppTheme.primaryViolet
                              : AppTheme.primaryViolet.withOpacity(0.4),
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                          backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: (e.value['total_count'] as int).toDouble(),
                              color: const Color(0xFFF1F5F9)),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= reversedHistory.length)
                                return const SizedBox.shrink();
                              final date = DateTime.parse(
                                  reversedHistory[idx]['week_date']);
                              return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('${date.month}/${date.day}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textSub)));
                            })),
                    leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) => Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                    fontSize: 10, color: AppTheme.textSub)))),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color:
                          const Color(0xFFCBD5E1), // [FIX] 더 진한 회색 (Slate-300)
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

  Widget _buildDetailedAttendanceSection(String weekId,
      {bool isLoading = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 20, 24, 16),
          child: Text('조별 상세 현황',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textMain)),
        ),
        ref
            .watch(departmentWeeklyAttendanceProvider(
                '${widget.departmentId}:$weekId'))
            .maybeWhen(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              skipError: true,
              data: (data) {
                final groups = List<Map<String, dynamic>>.from(data['groups']);
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: groups.length,
                  itemBuilder: (context, index) => _GroupAttendanceAccordion(
                      group: groups[index], isCoupleMode: widget.isCoupleMode),
                );
              },
              orElse: () => _buildAttendanceDetailSkeleton(),
            ),
      ],
    );
  }

  Widget _buildAttendanceDetailSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: List.generate(
            4,
            (index) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 80,
                                height: 14,
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4))),
                            const SizedBox(height: 6),
                            Container(
                                width: 120,
                                height: 12,
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4))),
                          ],
                        ),
                      ),
                      Container(
                          width: 48,
                          height: 28,
                          decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8))),
                    ],
                  ),
                )),
      ),
    );
  }
}

class _GroupAttendanceAccordion extends StatefulWidget {
  final Map<String, dynamic> group;
  final bool isCoupleMode;
  const _GroupAttendanceAccordion(
      {required this.group, this.isCoupleMode = false});
  @override
  State<_GroupAttendanceAccordion> createState() =>
      _GroupAttendanceAccordionState();
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
    final bool isSubmitted = group['is_submitted'] ?? true;
    final bool isGroupNoMeeting = group['is_group_no_meeting'] == true;
    final members = List<Map<String, dynamic>>.from(group['members']);
    // [SORT] 부부형이면 marriage key(부부묶음+가나다), 아니면 이름순
    members.sort((a, b) {
      final n1 = (a['full_name'] as String?)?.trim() ?? '';
      final n2 = (b['full_name'] as String?)?.trim() ?? '';
      if (!widget.isCoupleMode) return n1.compareTo(n2);
      String getMarriageKey(Map<String, dynamic> m) {
        final name = (m['full_name'] as String?)?.trim() ?? '';
        final spouse = (m['spouse_name'] as String?)?.trim() ?? '';
        if (spouse.isEmpty) return name;
        final list = [name, spouse];
        list.sort();
        return list.join('_');
      }

      final k1 = getMarriageKey(a);
      final k2 = getMarriageKey(b);
      if (k1 != k2) return k1.compareTo(k2);
      return n1.compareTo(n2);
    });
    final presentCount = group['present_count'];
    final totalCount = group['total_count'];
    final rate = totalCount > 0 ? (presentCount / totalCount * 100).toInt() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _isExpanded
                ? AppTheme.primaryViolet.withOpacity(0.3)
                : AppTheme.divider,
            width: _isExpanded ? 1.5 : 1.0),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            title: Text(group['name'],
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            subtitle: isSubmitted
                ? Text(
                    isGroupNoMeeting
                        ? '새가족 모임 없음'
                        : '출석 $presentCount명 / 총 $totalCount명',
                    style:
                        const TextStyle(fontSize: 12, color: AppTheme.textSub))
                : const Text('이번 주 출석 미입력',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSubmitted && isGroupNoMeeting)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppTheme.accentViolet,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('모임 없음',
                        style: TextStyle(
                            color: AppTheme.primaryViolet,
                            fontWeight: FontWeight.w900,
                            fontSize: 12)),
                  )
                else if (isSubmitted)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: _getRateColor(rate).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('$rate%',
                        style: TextStyle(
                            color: _getRateColor(rate),
                            fontWeight: FontWeight.w900,
                            fontSize: 12)),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('미제출',
                        style: TextStyle(
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w900,
                            fontSize: 12)),
                  ),
                const SizedBox(width: 8),
                Icon(
                    _isExpanded
                        ? lucide.LucideIcons.chevronUp
                        : lucide.LucideIcons.chevronDown,
                    size: 18),
              ],
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border)),
                child: isSubmitted
                    ? Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        children: members.map((m) {
                          final isPresent =
                              m['status'] == 'present' || m['status'] == 'late';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                                color: isPresent
                                    ? AppTheme.accentViolet
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: isPresent
                                        ? AppTheme.primaryViolet
                                            .withOpacity(0.3)
                                        : AppTheme.border)),
                            child: Text(m['full_name'],
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isPresent
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isPresent
                                        ? AppTheme.primaryViolet
                                        : AppTheme.textSub)),
                          );
                        }).toList(),
                      )
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('조장님이 아직 이번 주 출석을 입력하지 않았습니다.',
                              style: TextStyle(
                                  color: AppTheme.textSub,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
