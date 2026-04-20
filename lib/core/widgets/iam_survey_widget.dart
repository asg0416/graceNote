// lib/core/widgets/iam_survey_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:grace_note/core/models/in_app_message.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';

class IamSurveyWidget extends ConsumerStatefulWidget {
  final String messageId;
  final List<SurveyQuestion> questions;
  final VoidCallback? onSubmitted;

  const IamSurveyWidget({
    super.key,
    required this.messageId,
    required this.questions,
    this.onSubmitted,
  });

  @override
  ConsumerState<IamSurveyWidget> createState() => _IamSurveyWidgetState();
}

class _IamSurveyWidgetState extends ConsumerState<IamSurveyWidget> {
  int _page = 0;
  final Map<String, dynamic> _answers = {};
  bool _isSubmitting = false;
  String? _errorMsg;
  bool _forward = true;

  SurveyQuestion get _current => widget.questions[_page];
  int get _total => widget.questions.length;

  bool get _currentAnswered {
    if (!_current.required) return true;
    final val = _answers[_current.id];
    if (val == null) return false;
    if (val is String) return val.trim().isNotEmpty;
    if (val is List) return val.isNotEmpty;
    if (val is int) return val > 0;
    return false;
  }

  void _goNext() {
    if (!_currentAnswered) {
      SnackBarUtil.showSnackBar(context, message: '필수 질문에 응답해주세요.');
      return;
    }
    if (_page < _total - 1) {
      setState(() {
        _forward = true;
        _page++;
        _errorMsg = null;
      });
    }
  }

  void _goPrev() {
    if (_page > 0) {
      setState(() {
        _forward = false;
        _page--;
        _errorMsg = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_currentAnswered) {
      SnackBarUtil.showSnackBar(context, message: '필수 질문에 응답해주세요.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMsg = null;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('로그인이 필요합니다.');

      final answers = widget.questions
          .where((q) => _answers.containsKey(q.id))
          .map((q) => {'question_id': q.id, 'value': _answers[q.id]})
          .toList();

      await Supabase.instance.client.from('iam_survey_responses').insert({
        'message_id': widget.messageId,
        'user_id': userId,
        'answers': answers,
      });

      if (!mounted) return;
      SnackBarUtil.showSnackBar(
        context,
        message: '응답이 제출되었습니다. 소중한 의견 감사합니다!',
      );
      widget.onSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      debugPrint('IamSurveyWidget submit error: $e');
      final msg = e.toString();
      final isDuplicate = msg.contains('23505') ||
          msg.contains('unique') ||
          msg.contains('duplicate');
      setState(() {
        _errorMsg = isDuplicate
            ? '이미 응답하신 설문입니다.'
            : '제출에 실패했습니다. 다시 시도해 주세요.';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24, color: AppTheme.border),

        // 진행 표시
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_page + 1) / _total,
                  backgroundColor: AppTheme.border,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primaryViolet),
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_page + 1} / $_total',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSub,
                fontFamily: 'Pretendard',
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 질문 슬라이드
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) {
            final offset = _forward
                ? const Offset(0.08, 0)
                : const Offset(-0.08, 0);
            return SlideTransition(
              position: Tween<Offset>(
                begin: offset,
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_page),
            child: _buildQuestion(_current),
          ),
        ),

        if (_errorMsg != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorMsg!,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.error,
              fontFamily: 'Pretendard',
            ),
          ),
        ],

        const SizedBox(height: 16),

        // 이전 / 다음·제출 버튼
        Row(
          children: [
            if (_page > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _goPrev,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSub,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '이전',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSubmitting
                    ? null
                    : (_page < _total - 1 ? _goNext : _submit),
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
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _page < _total - 1 ? '다음' : '제출하기',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Pretendard',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuestion(SurveyQuestion q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                q.text,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                  fontFamily: 'Pretendard',
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (q.required)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '필수',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.error,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (q.type == 'star_rating') _buildStarRating(q),
        if (q.type == 'radio') _buildRadio(q),
        if (q.type == 'checkbox') _buildCheckbox(q),
        if (q.type == 'text') _buildTextField(q),
      ],
    );
  }

  Widget _buildStarRating(SurveyQuestion q) {
    final selected = _answers[q.id] as int? ?? 0;
    return Row(
      children: List.generate(5, (i) {
        final filled = i < selected;
        return GestureDetector(
          onTap: () => setState(() => _answers[q.id] = i + 1),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 32,
              color: filled ? AppTheme.warning : AppTheme.border,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildRadio(SurveyQuestion q) {
    final selected = _answers[q.id] as String?;
    return Column(
      children: q.options
          .map(
            (opt) => RadioListTile<String>(
              value: opt,
              groupValue: selected,
              onChanged: (v) => setState(() => _answers[q.id] = v),
              title: Text(
                opt,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'Pretendard',
                  color: AppTheme.textMain,
                ),
              ),
              activeColor: AppTheme.primaryViolet,
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCheckbox(SurveyQuestion q) {
    final selected = (_answers[q.id] as List?)?.cast<String>() ?? [];
    return Column(
      children: q.options
          .map(
            (opt) => CheckboxListTile(
              value: selected.contains(opt),
              onChanged: (v) {
                setState(() {
                  final next = List<String>.from(selected);
                  if (v == true) {
                    next.add(opt);
                  } else {
                    next.remove(opt);
                  }
                  _answers[q.id] = next;
                });
              },
              title: Text(
                opt,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'Pretendard',
                  color: AppTheme.textMain,
                ),
              ),
              activeColor: AppTheme.primaryViolet,
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
            ),
          )
          .toList(),
    );
  }

  Widget _buildTextField(SurveyQuestion q) {
    return TextField(
      maxLines: 4,
      maxLength: 500,
      onChanged: (v) => setState(() => _answers[q.id] = v),
      style: const TextStyle(
        fontSize: 13,
        fontFamily: 'Pretendard',
        color: AppTheme.textMain,
      ),
      decoration: InputDecoration(
        hintText: '답변을 입력해주세요',
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
    );
  }
}
