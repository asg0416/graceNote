// lib/core/widgets/iam_card.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:url_launcher/url_launcher.dart';
import 'package:expandable_page_view/expandable_page_view.dart';

import 'package:grace_note/core/models/in_app_message.dart';
import 'package:grace_note/core/providers/iam_provider.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/widgets/iam_survey_widget.dart';

class IamCard extends ConsumerStatefulWidget {
  final InAppMessage message;
  final bool showHandle;    // slide_up: true, modal: false
  final bool isModal;       // modal: true → SafeArea bottom 무시
  final VoidCallback? onDismiss;

  const IamCard({
    super.key,
    required this.message,
    this.showHandle = false,
    this.isModal = false,
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
  bool _isUserTouching = false;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 모달이 렌더링될 때 이미지들을 미리 로딩(캐싱)하여 대기/깜빡임 최소화
    if (widget.message.imageUrl != null) {
      precacheImage(NetworkImage(widget.message.imageUrl!), context);
    }
    for (final slide in widget.message.slides) {
      if (slide.imageUrl != null) {
        precacheImage(NetworkImage(slide.imageUrl!), context);
      }
    }
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    if (_isUserTouching) return; // 사용자가 터치 중이면 타이머 재시작 금지

    _autoSlideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageCtrl.hasClients || _isUserTouching) return;
      _pageCtrl.animateToPage(
        _pageCtrl.page!.round() + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoSlide() {
    _autoSlideTimer?.cancel();
  }

  void _resumeAutoSlide() {
    if (widget.message.isSlideMode && widget.message.slides.length > 1) {
      if (!_isUserTouching) {
        _startAutoSlide();
      }
    }
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

  Widget _buildTopImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: Image.network(
        url,
        width: double.infinity,
        // height 제한을 풀고 비율에 맞게 높이가 자동 조절되도록 설정 (단일 모드)
        fit: BoxFit.fitWidth,
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
    if (slide.imageUrl == null) return const SizedBox.shrink();
    return Image.network(
      slide.imageUrl!,
      width: double.infinity,
      fit: BoxFit.fitWidth, // expandable_page_view를 사용하므로 원본 높이 그대로 자동 조절
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          width: double.infinity,
          height: 180, // 로딩 중 모달이 완전히 찌그러지는 것을 방지
          color: AppTheme.secondaryBackground.withValues(alpha: 0.3),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  /// 현재 슬라이드 텍스트 (PageView 밖에서 렌더링 → 내용에 맞게 높이 자동)
  Widget _buildSlideText(IamSlide slide) {
    if (slide.title.isEmpty && slide.body.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
              customStylesBuilder: (el) =>
                  el.localName == 'p' ? {'margin': '0', 'padding': '0'} : null,
              textStyle: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSub,
                fontFamily: 'Pretendard',
                height: 1.55,
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
    // 모달일 때는 SafeArea bottom을 무시하고 고정 패딩 사용
    final bottomPad = widget.isModal ? 0.0 : MediaQuery.of(context).padding.bottom;

    return Listener(
      behavior: HitTestBehavior.translucent, // 이벤트가 자식 위젯을 통과해서 잡히도록 설정
      onPointerDown: (_) {
        _isUserTouching = true;
        _pauseAutoSlide();
      },
      onPointerUp: (_) {
        _isUserTouching = false;
        _resumeAutoSlide();
      },
      onPointerCancel: (_) {
        _isUserTouching = false;
        _resumeAutoSlide();
      },
      child: Column(
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

        // ── 헤더 영역 (배지 + 제목) — imageOnly일 때 숨김 ──────────────
        if (!message.imageOnly) ...[
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
        ],

        // ── 슬라이드 모드 ────────────────────────────────────────────
        if (hasSlides) ...[
          // 이미지만 PageView에, 텍스트는 아래서 별도 렌더링 (동적 높이 적용)
          if (message.slides.any((s) => s.imageUrl != null))
            ExpandablePageView.builder(
              controller: _pageCtrl,
              itemCount: message.slides.length > 1
                  ? message.slides.length * _loopMult
                  : 1,
              onPageChanged: (i) {
                setState(() => _currentSlide = i % message.slides.length);
                if (message.slides.length > 1) {
                  if (!_isUserTouching) {
                    _startAutoSlide();
                  }
                }
              },
              itemBuilder: (_, i) =>
                  _buildSlide(message.slides[i % message.slides.length]),
            ),
          _buildDots(message.slides.length),
          // 현재 슬라이드 텍스트 — 내용 높이에 맞게 자동 조정
          if (!message.imageOnly)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_currentSlide),
                child: _buildSlideText(
                    message.slides[_currentSlide % message.slides.length]),
              ),
            ),
          const SizedBox(height: 4),
        ],

        // ── 단일 본문 — 비어있거나 imageOnly면 숨김 ─────────────────────
        if (!hasSlides && message.type != IamType.survey &&
            message.body.isNotEmpty && !message.imageOnly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: HtmlWidget(
              message.body,
              customStylesBuilder: (el) =>
                  el.localName == 'p' ? {'margin': '0', 'padding': '0'} : null,
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
            child: ref.watch(iamSurveyAnsweredProvider(message.id)).when(
              data: (answered) {
                if (answered) {
                  // 이미 응답한 경우 카드 자체를 숨김 (다시 보지 않기와 동일)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _dismissPermanently();
                  });
                  return const SizedBox.shrink();
                }
                return RepaintBoundary(
                  child: IamSurveyWidget(
                    messageId: message.id,
                    questions: message.surveyQuestions,
                    onSubmitted: _dismissPermanently,
                  ),
                );
              },
              loading: () => const SizedBox(height: 40),
              error: (_, __) => RepaintBoundary(
                child: IamSurveyWidget(
                  messageId: message.id,
                  questions: message.surveyQuestions,
                  onSubmitted: _dismissPermanently,
                ),
              ),
            ),
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1, color: AppTheme.border),
              Padding(
                padding: EdgeInsets.symmetric(vertical: bottomPad > 10 ? bottomPad / 2 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
              ),
            ],
          ),
        ),
      ],
    );
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
