import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

class SeasonContextChip extends ConsumerWidget {
  final String departmentId;
  final DateTime weekDate;
  final EdgeInsetsGeometry margin;
  final bool iconOnly;

  const SeasonContextChip({
    super.key,
    required this.departmentId,
    required this.weekDate,
    this.margin = EdgeInsets.zero,
    this.iconOnly = false,
  });

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _shortDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    return '${parsed.month}/${parsed.day}';
  }

  void _showSeasonSheet(
    BuildContext context, {
    required bool hasSeason,
    required String? title,
    required String period,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F0FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        lucide.LucideIcons.calendarDays,
                        size: 20,
                        color: AppTheme.primaryViolet,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '조편성 시즌',
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          fontFamily: 'Pretendard',
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  hasSeason ? title! : '등록된 시즌 없음',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    fontFamily: 'Pretendard',
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasSeason
                      ? (period.isEmpty ? '기간 정보가 없습니다.' : period)
                      : '이 주차는 현재 명부 기준으로 표시됩니다.',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSub,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (departmentId.isEmpty) return const SizedBox.shrink();

    final seasonAsync = ref.watch(
      regroupingSeasonForWeekProvider('$departmentId:${_dateText(weekDate)}'),
    );

    return seasonAsync.maybeWhen(
      data: (season) {
        final title = season?['title']?.toString();
        final start = _shortDate(season?['effective_week_date']);
        final end = _shortDate(season?['end_week_date']);
        final hasSeason = title != null && title.isNotEmpty;
        final period = hasSeason
            ? [start, end.isEmpty ? '진행 중' : end]
                .where((value) => value.isNotEmpty)
                .join('~')
            : '';
        void showSeasonSheet() => _showSeasonSheet(
              context,
              hasSeason: hasSeason,
              title: title,
              period: period,
            );

        if (iconOnly) {
          return Padding(
            padding: margin,
            child: IconButton(
              onPressed: showSeasonSheet,
              tooltip: '조편성 시즌',
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                backgroundColor: const Color(0xFFF7F4FF),
                foregroundColor: AppTheme.primaryViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(
                lucide.LucideIcons.calendarDays,
                size: 18,
              ),
            ),
          );
        }

        return Padding(
          padding: margin,
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: showSeasonSheet,
              style: TextButton.styleFrom(
                minimumSize: const Size(40, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                foregroundColor: AppTheme.textSub,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(
                lucide.LucideIcons.calendarDays,
                size: 14,
                color: AppTheme.primaryViolet,
              ),
              label: const Text(
                '시즌 정보',
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSub,
                  fontFamily: 'Pretendard',
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
