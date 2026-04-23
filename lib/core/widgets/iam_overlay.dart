// lib/core/widgets/iam_overlay.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grace_note/core/models/in_app_message.dart';
import 'package:grace_note/core/providers/iam_provider.dart';
import 'package:grace_note/core/widgets/iam_card.dart';

/// visibleIamProvider 를 감시하다가 메시지가 생기면 오버레이를 렌더링.
/// displayType == slideUp  → 하단 슬라이드업 시트 + 반투명 배경
/// displayType == modal    → 중앙 모달 + 반투명 배경
class IamOverlay extends ConsumerWidget {
  final Widget child;
  const IamOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(visibleIamProvider);
    if (messages.isEmpty) return child;

    final message = messages.first;

    return Stack(
      children: [
        child,
        if (message.displayType == IamDisplayType.slideUp)
          _SlideUpOverlay(message: message)
        else
          _ModalOverlay(message: message),
      ],
    );
  }
}

// ── 공통 X 닫기 버튼 ──────────────────────────────────────────────────

class _CloseButton extends ConsumerWidget {
  final InAppMessage message;
  final Color color;

  const _CloseButton({required this.message, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          ref.read(iamSessionDismissProvider.notifier).dismiss(message.id),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(
          Icons.close_rounded,
          size: 20,
          color: color,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slide-up 시트 ─────────────────────────────────────────────────────

class _SlideUpOverlay extends StatelessWidget {
  final InAppMessage message;
  const _SlideUpOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 어두운 반투명 배경 (modal과 동일한 처리)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // 앱 콘텐츠로 터치 전파 방지
                child: Container(
                  color: const Color(0x4D000000), // 30% 어두운 배경
                ),
              ),
            ),

            // X 버튼 + 카드: Column으로 묶어 hit test 범위에 포함
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _CloseButton(
                      message: message,
                      color: Colors.white.withValues(alpha: 0.80),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.82 -
                          MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: SingleChildScrollView(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 24,
                              offset: Offset(0, -4),
                            ),
                          ],
                        ),
                        child: IamCard(
                          message: message,
                          showHandle: true,
                        ),
                      ),
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
}

// ── 중앙 모달 ──────────────────────────────────────────────────────────

class _ModalOverlay extends StatelessWidget {
  final InAppMessage message;
  const _ModalOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 어두운 반투명 배경
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // 앱 콘텐츠로 터치 전파 방지
                child: Container(color: const Color(0x80000000)),
              ),
            ),

            // X 버튼 + 카드: 키보드 높이만큼 bottom 축소 후 중앙 배치 + 스크롤 가능
            Positioned(
              left: 24,
              right: 24,
              top: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom,
              child: Center(
                child: SingleChildScrollView(
                  // shrinkWrap: true 로 스크롤뷰가 컨텐츠 크기에 맞춰 줄어들어야
                  // Center 가 올바르게 수직 중앙 배치 가능
                  shrinkWrap: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: _CloseButton(
                          message: message,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: IamCard(
                            message: message,
                            showHandle: false,
                            isModal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
