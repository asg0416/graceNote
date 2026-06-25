import 'package:flutter/material.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart' hide DateFormat;

class EffectiveWeekPickerField extends StatelessWidget {
  final DateTime effectiveWeekDate;
  final bool enabled;
  final VoidCallback? onTap;

  const EffectiveWeekPickerField({
    super.key,
    required this.effectiveWeekDate,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.calendarDays,
                size: 18,
                color: AppTheme.primaryViolet,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  DateFormat('yyyy. M. d.').format(effectiveWeekDate),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
              const Text(
                '이 주차부터 반영',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSub,
                  fontFamily: 'Pretendard',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
