import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SnackBarUtil {
  static void showSnackBar(
    BuildContext context, {
    required String message,
    bool isError = false,
    String? technicalDetails,
    Duration? duration,
    SnackBarAction? action,
  }) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    // Remove previous snackbar instantly for better UX
    scaffoldMessenger.removeCurrentSnackBar();

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: isError ? const Color(0xFFF87171) : const Color(0xFF34D399),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (technicalDetails != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: technicalDetails));
                    scaffoldMessenger.hideCurrentSnackBar();
                    showSnackBar(context, message: '에러 정보가 복사되었습니다.');
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF1F2937).withOpacity(0.95), // Premium Dark Gray
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isError ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        duration: duration ?? const Duration(seconds: 3),
        action: action,
        elevation: 10,
      ),
    );
  }
}
