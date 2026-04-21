import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SnackBarUtil {
  static OverlayEntry? _current;

  static void showSnackBar(
    BuildContext context, {
    required String message,
    bool isError = false,
    String? technicalDetails,
    Duration? duration,
    SnackBarAction? action,
  }) {
    _dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);
    final effectiveDuration = duration ?? const Duration(seconds: 3);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        message: message,
        isError: isError,
        duration: effectiveDuration,
        onDismiss: () => _dismissEntry(entry),
        copyButton: technicalDetails != null
            ? () {
                Clipboard.setData(ClipboardData(text: technicalDetails));
                _dismissEntry(entry);
                showSnackBar(context, message: '에러 정보가 복사되었습니다.');
              }
            : null,
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  static void _dismiss() {
    _current?.remove();
    _current = null;
  }

  static void _dismissEntry(OverlayEntry entry) {
    if (_current == entry) _dismiss();
  }
}

class _Toast extends StatefulWidget {
  final String message;
  final bool isError;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? copyButton;

  const _Toast({
    required this.message,
    required this.isError,
    required this.duration,
    required this.onDismiss,
    this.copyButton,
  });

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).viewInsets.bottom +
          MediaQuery.of(context).padding.bottom +
          32,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937).withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isError
                      ? Colors.red.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    color: widget.isError
                        ? const Color(0xFFF87171)
                        : const Color(0xFF34D399),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (widget.copyButton != null)
                    InkWell(
                      onTap: widget.copyButton,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.copy_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
