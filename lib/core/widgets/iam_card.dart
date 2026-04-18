// lib/core/widgets/iam_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:url_launcher/url_launcher.dart';

import 'package:grace_note/core/models/in_app_message.dart';
import 'package:grace_note/core/providers/iam_provider.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/widgets/iam_survey_widget.dart';

class IamCard extends ConsumerWidget {
  final InAppMessage message;
  final bool showHandle; // slide_up: true, modal: false

  const IamCard({
    super.key,
    required this.message,
    this.showHandle = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        showHandle ? 8 : 20,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들바 (slide_up 전용)
          if (showHandle)
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

          // 타입 배지
          _IamTypeBadge(type: message.type),
          const SizedBox(height: 10),

          // 제목
          Text(
            message.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
              fontFamily: 'Pretendard',
              letterSpacing: -0.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),

          // HTML 본문
          HtmlWidget(
            message.body,
            textStyle: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSub,
              fontFamily: 'Pretendard',
              height: 1.55,
            ),
          ),

          // Survey UI (survey 타입일 경우)
          if (message.type == IamType.survey) ...[
            const SizedBox(height: 4),
            IamSurveyWidget(messageId: message.id),
          ],

          // CTA 버튼 (있을 경우)
          if (message.ctaLabel != null && message.ctaUrl != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _launchCta(message.ctaUrl!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryViolet,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Pretendard',
                    letterSpacing: -0.2,
                  ),
                ),
                child: Text(message.ctaLabel!),
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 8),

          // 하단 dismiss 버튼 3종
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _DismissTextButton(
                label: '닫기',
                onTap: () => ref
                    .read(iamSessionDismissProvider.notifier)
                    .dismiss(message.id),
              ),
              const SizedBox(width: 8),
              _DismissTextButton(
                label: '오늘 그만보기',
                onTap: () => ref
                    .read(iamDismissNotifierProvider.notifier)
                    .snoozeToday(message.id),
              ),
              const SizedBox(width: 8),
              _DismissTextButton(
                label: '다시 보지 않기',
                onTap: () => ref
                    .read(iamDismissNotifierProvider.notifier)
                    .dismissPermanently(message.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _launchCta(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── 타입 배지 ────────────────────────────────────────────────────────

class _IamTypeBadge extends StatelessWidget {
  final IamType type;
  const _IamTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (type) {
      IamType.announcement => (
        lucide.LucideIcons.bell,
        '공지',
        AppTheme.primaryViolet,
      ),
      IamType.update => (
        lucide.LucideIcons.refreshCw,
        '업데이트',
        const Color(0xFF0EA5E9),
      ),
      IamType.survey => (
        lucide.LucideIcons.star,
        '만족도 조사',
        AppTheme.warning,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
              fontFamily: 'Pretendard',
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dismiss 텍스트 버튼 ────────────────────────────────────────────────

class _DismissTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DismissTextButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSub.withValues(alpha: 0.7),
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.textSub.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}
