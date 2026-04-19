// lib/core/widgets/iam_survey_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';

class IamSurveyWidget extends ConsumerStatefulWidget {
  final String messageId;
  final VoidCallback? onSubmitted;

  const IamSurveyWidget({
    super.key,
    required this.messageId,
    this.onSubmitted,
  });

  @override
  ConsumerState<IamSurveyWidget> createState() => _IamSurveyWidgetState();
}

class _IamSurveyWidgetState extends ConsumerState<IamSurveyWidget> {
  int _selectedRating  = 0;
  final _commentCtrl   = TextEditingController();
  bool _isSubmitting   = false;
  String? _errorMsg;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedRating == 0) return;
    setState(() { _isSubmitting = true; _errorMsg = null; });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('로그인이 필요합니다.');

      await Supabase.instance.client.from('iam_survey_responses').insert({
        'message_id': widget.messageId,
        'user_id':    userId,
        'rating':     _selectedRating,
        'comment':    _commentCtrl.text.trim().isEmpty
                        ? null
                        : _commentCtrl.text.trim(),
      });

      if (!mounted) return;
      SnackBarUtil.showSnackBar(
        context,
        message: '응답이 제출되었습니다. 소중한 의견 감사합니다!',
      );
      widget.onSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = '제출에 실패했습니다. 다시 시도해 주세요.'; });
    } finally {
      if (mounted) setState(() { _isSubmitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24, color: AppTheme.border),
        const Text(
          '만족도를 알려주세요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMain,
            fontFamily: 'Pretendard',
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        // 별점
        Row(
          children: List.generate(5, (i) {
            final filled = i < _selectedRating;
            return GestureDetector(
              onTap: () => setState(() => _selectedRating = i + 1),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 28,
                  color: filled ? AppTheme.warning : AppTheme.border,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        // 코멘트 (선택)
        TextField(
          controller: _commentCtrl,
          maxLines: 2,
          maxLength: 200,
          style: const TextStyle(
            fontSize: 13,
            fontFamily: 'Pretendard',
            color: AppTheme.textMain,
          ),
          decoration: InputDecoration(
            hintText: '의견을 남겨주세요 (선택)',
            counterStyle: const TextStyle(
              fontSize: 10,
              color: AppTheme.textSub,
              fontFamily: 'Pretendard',
            ),
            filled: true,
            fillColor: AppTheme.secondaryBackground,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryViolet, width: 1.5),
            ),
          ),
        ),
        if (_errorMsg != null) ...[
          const SizedBox(height: 6),
          Text(_errorMsg!, style: const TextStyle(
            fontSize: 11, color: AppTheme.error, fontFamily: 'Pretendard',
          )),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selectedRating > 0 && !_isSubmitting) ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryViolet,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.border,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white,
                    ),
                  )
                : const Text('제출하기',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      fontFamily: 'Pretendard',
                    )),
          ),
        ),
      ],
    );
  }

}
