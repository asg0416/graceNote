import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'dart:ui';
import 'dart:math' as math;

class PrayerShareScreen extends StatelessWidget {
  final String shareText;

  const PrayerShareScreen({
    super.key,
    required this.shareText,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '기도제목 공유하기',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.textMain,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textSub),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '미리보기',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryViolet,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      shareText,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textMain,
                        height: 1.7,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildActionPanel(context),
        ],
      ),
    );
  }

  Widget _buildActionPanel(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 32 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildShareOption(
            context,
            icon: Icons.copy_rounded,
            label: '텍스트 복사하기',
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: shareText));
              if (context.mounted) {
                SnackBarUtil.showSnackBar(context, message: '클립보드에 복사되었습니다.');
              }
            },
          ),
          const SizedBox(height: 12),
          _buildShareOption(
            context,
            icon: Icons.share_rounded,
            label: '시스템 공유하기',
            onTap: () {
              Share.share(shareText);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildShareOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryViolet.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primaryViolet, size: 22),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF94A3B8), size: 14),
          ],
        ),
      ),
    );
  }
}
