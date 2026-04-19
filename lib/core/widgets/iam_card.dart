// lib/core/widgets/iam_card.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:url_launcher/url_launcher.dart';

import 'package:grace_note/core/models/in_app_message.dart';
import 'package:grace_note/core/providers/iam_provider.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/widgets/iam_survey_widget.dart';

class IamCard extends ConsumerStatefulWidget {
  final InAppMessage message;
  final bool showHandle;    // slide_up: true, modal: false
  final VoidCallback? onDismiss;

  const IamCard({
    super.key,
    required this.message,
    this.showHandle = false,
    this.onDismiss,
  });

  @override
  ConsumerState<IamCard> createState() => _IamCardState();
}

class _IamCardState extends ConsumerState<IamCard> {
  static const _loopMult = 500;
  late final PageController _pageCtrl;
  int _currentSlide = 0;
  Timer? _autoSlideTimer;

  @override
  void initState() {
    super.initState();
    final slides = widget.message.slides;
    final initialPage = slides.length > 1
        ? slides.length * (_loopMult ~/ 2)
        : 0;
    _pageCtrl = PageController(initialPage: initialPage);
    if (widget.message.isSlideMode && slides.length > 1) {
      _startAutoSlide();
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      _pageCtrl.animateToPage(
        _pageCtrl.page!.round() + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  // ── dismiss helpers ──────────────────────────────────────────────

  void _snoozeToday() {
    ref.read(iamDismissNotifierProvider.notifier).snoozeToday(widget.message.id);
    widget.onDismiss?.call();
  }

  void _dismissPermanently() {
    ref.read(iamDismissNotifierProvider.notifier).dismissPermanently(widget.message.id);
    widget.onDismiss?.call();
  }

  // ── builders ─────────────────────────────────────────────────────

  /// 단일 모드 상단 이미지 (full-width)
  Widget _buildTopImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: Image.network(
        url,
        width: double.infinity,
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                height: 180,
                color: AppTheme.secondaryBackground,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
      ),
    );
  }

  /// 슬라이드 1페이지
  Widget _buildSlide(IamSlide slide) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slide.imageUrl != null)
            Image.network(
              slide.imageUrl!,
              width: double.infinity,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (slide.title.isNotEmpty) ...[
                  Text(
                    slide.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                      fontFamily: 'Pretendard',
                      letterSpacing: -0.4,
                      height: 1.3,
                    ),
                  ),
                  if (slide.body.isNotEmpty) const SizedBox(height: 6),
                ],
                if (slide.body.isNotEmpty)
                  HtmlWidget(
                    slide.body,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSub,
                      fontFamily: 'Pretendard',
                      height: 1.55,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 슬라이드 점 인디케이터
  Widget _buildDots(int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == _currentSlide;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.primaryViolet
                  : AppTheme.primaryViolet.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final hasSlides = message.isSlideMode;
    final bottomPad = MediaQuery.of(context).padding.bottom + 16;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 핸들바 ──────────────────────────────────────────────────
        if (widget.showHandle)
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

        // ── 단일 모드 상단 이미지 ────────────────────────────────────
        if (!hasSlides && message.imageUrl != null)
          _buildTopImage(message.imageUrl!),

        // ── 헤더 영역 (배지 + 제목) ──────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            (!hasSlides && message.imageUrl != null) ? 14 : (widget.showHandle ? 0 : 20),
            20,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _IamTypeBadge(type: message.type),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    fontFamily: 'Pretendard',
                    letterSpacing: -0.4,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ── 슬라이드 모드 ────────────────────────────────────────────
        if (hasSlides) ...[
          SizedBox(
            height: _slideHeight(message.slides),
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: message.slides.length > 1
                  ? message.slides.length * _loopMult
                  : 1,
              onPageChanged: (i) {
                setState(() => _currentSlide = i % message.slides.length);
                if (message.slides.length > 1) _startAutoSlide();
              },
              itemBuilder: (_, i) =>
                  _buildSlide(message.slides[i % message.slides.length]),
            ),
          ),
          _buildDots(message.slides.length),
          const SizedBox(height: 4),
        ],

        // ── 단일 본문 ────────────────────────────────────────────────
        if (!hasSlides)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: HtmlWidget(
              message.body,
              textStyle: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSub,
                fontFamily: 'Pretendard',
                height: 1.55,
              ),
            ),
          ),

        // ── 만족도 조사 ──────────────────────────────────────────────
        if (message.type == IamType.survey) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: IamSurveyWidget(messageId: message.id),
          ),
        ],

        // ── CTA 버튼 ─────────────────────────────────────────────────
        if (message.ctaLabel != null && message.ctaUrl != null) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
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
          ),
        ],

        // ── 하단 dismiss 영역 ────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
          child: Column(
            children: [
              const Divider(height: 1, color: AppTheme.border),
              const SizedBox(height: 10),
              Row(
                children: [
                  _DismissTextButton(
                    label: '다시 보지 않기',
                    onTap: _dismissPermanently,
                  ),
                  const Spacer(),
                  _DismissTextButton(
                    label: '오늘 그만보기',
                    onTap: _snoozeToday,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 슬라이드 높이: 이미지 유무에 따라 결정
  double _slideHeight(List<IamSlide> slides) {
    final hasImage = slides.any((s) => s.imageUrl != null);
    return hasImage ? 380 : 220;
  }

  Future<void> _launchCta(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme != 'https' && uri.scheme != 'http') return;
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

  const _DismissTextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 1),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSub.withValues(alpha: 0.65),
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.textSub.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}
