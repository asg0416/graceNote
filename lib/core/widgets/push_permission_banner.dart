import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/services/push_notification_service.dart';
import 'package:grace_note/core/services/web_push_runtime.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

enum _BannerState { visible, requesting, denied, dismissed }

class PushPermissionBanner extends ConsumerStatefulWidget {
  const PushPermissionBanner({super.key});

  @override
  ConsumerState<PushPermissionBanner> createState() =>
      _PushPermissionBannerState();
}

class _PushPermissionBannerState extends ConsumerState<PushPermissionBanner>
    with SingleTickerProviderStateMixin {
  _BannerState _state = _BannerState.visible;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _animController.reverse();
    if (mounted) setState(() => _state = _BannerState.dismissed);
  }

  Future<void> _requestPermission() async {
    // iOS Safari: permission request must originate from a user gesture context.
    // This onTap handler qualifies as a user gesture.
    setState(() => _state = _BannerState.requesting);

    final granted =
        await PushNotificationService().requestPermissionAndSaveToken();

    if (!mounted) return;

    if (granted) {
      ref.invalidate(hasFcmTokenProvider);
      await _dismiss();
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '🔔 알림이 설정되었습니다! 그레이스노트의 다양한 소식을 전해드릴게요.',
          duration: const Duration(seconds: 4),
        );
      }
    } else {
      // Check if browser has explicitly denied (vs. just not asked yet)
      final isDenied = _isBrowserNotificationDenied();
      setState(
          () => _state = isDenied ? _BannerState.denied : _BannerState.visible);
    }
  }

  bool _isBrowserNotificationDenied() {
    try {
      return isBrowserNotificationDenied();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _state == _BannerState.dismissed) {
      return const SizedBox.shrink();
    }

    final tokenAsync = ref.watch(hasFcmTokenProvider);
    return tokenAsync.when(
      data: (hasToken) {
        if (hasToken) return const SizedBox.shrink();
        return ClipRect(
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _state == _BannerState.denied
                  ? _DeniedBanner(onDismiss: _dismiss)
                  : _PermissionBanner(
                      isRequesting: _state == _BannerState.requesting,
                      onAllow: _requestPermission,
                      onDismiss: _dismiss,
                    ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────
// 알림 허용 요청 배너
// ─────────────────────────────────────────────

class _PermissionBanner extends StatelessWidget {
  final bool isRequesting;
  final VoidCallback onAllow;
  final VoidCallback onDismiss;

  const _PermissionBanner({
    required this.isRequesting,
    required this.onAllow,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        color: AppTheme.accentViolet,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryViolet.withOpacity(0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _BannerIcon(
              icon: lucide.LucideIcons.bellRing,
              color: AppTheme.primaryViolet,
              bgColor: AppTheme.primaryViolet.withOpacity(0.12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '알림을 허용해 주세요',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                      fontFamily: 'Pretendard',
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '기도제목·공지사항 등 중요한 소식을 놓치지 마세요',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSub.withOpacity(0.75),
                      fontFamily: 'Pretendard',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isRequesting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryViolet,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: onAllow,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryViolet,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryViolet.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    '허용하기',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'Pretendard',
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            _DismissButton(onTap: onDismiss),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 알림 차단 상태 안내 배너
// ─────────────────────────────────────────────

class _DeniedBanner extends StatelessWidget {
  final VoidCallback onDismiss;

  const _DeniedBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.warning.withOpacity(0.22),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _BannerIcon(
              icon: lucide.LucideIcons.bellOff,
              color: AppTheme.warning,
              bgColor: AppTheme.warning.withOpacity(0.12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '알림이 차단되어 있어요',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                      fontFamily: 'Pretendard',
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '주소창 왼쪽 🔒 아이콘 → 알림 → 허용으로 변경해 주세요',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSub.withOpacity(0.75),
                      fontFamily: 'Pretendard',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _DismissButton(onTap: onDismiss),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 공통 서브위젯
// ─────────────────────────────────────────────

class _BannerIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _BannerIcon({
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _DismissButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DismissButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          lucide.LucideIcons.x,
          size: 15,
          color: AppTheme.textSub.withOpacity(0.4),
        ),
      ),
    );
  }
}
