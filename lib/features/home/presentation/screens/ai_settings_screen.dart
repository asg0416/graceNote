import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:grace_note/core/constants/app_constants.dart';
import '../../../../core/utils/snack_bar_util.dart';

class AISettingsScreen extends ConsumerStatefulWidget {
  const AISettingsScreen({super.key});

  @override
  ConsumerState<AISettingsScreen> createState() => _AISettingsScreenState();
}

class _AISettingsScreenState extends ConsumerState<AISettingsScreen> {
  late TextEditingController _indicatorController;
  late TextEditingController _endingController;
  late TextEditingController _shareIconController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(aiSettingsProvider);
    _indicatorController = TextEditingController(text: settings.customIndicator);
    _endingController = TextEditingController(text: settings.customEndingStyle);
    _shareIconController = TextEditingController(text: settings.shareHeaderIcon);
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    _endingController.dispose();
    _shareIconController.dispose();
    super.dispose();
  }

  String _getEndingStyleTitle(AIEndingStyle style) {
    switch (style) {
      case AIEndingStyle.pray: return '~하기를 기도합니다';
      case AIEndingStyle.desire: return '~하기를 소망합니다';
      case AIEndingStyle.wish: return '~하길 원합니다';
      case AIEndingStyle.to: return '~하도록 (개조식)';
      case AIEndingStyle.doing: return '~하기를';
      case AIEndingStyle.simple: return '~하기';
      case AIEndingStyle.custom: return '직접 입력';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('서비스 설정', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17, fontFamily: 'Pretendard', letterSpacing: -0.5)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('AI 정리 설정', '조원들의 기도제목을 더 깔끔하고 정성스럽게 정돈하기 위한 나만의 스타일을 만들어보세요.'),
            const SizedBox(height: 8),

            _buildSectionHeader('기도제목 구분 스타일', '항목을 나눌 때 사용할 기호를 선택하세요.'),
            _buildSelectionContainer(
              child: Column(
                children: [
                  _buildRadioTile(
                    title: '번호 매기기',
                    subtitle: '1. 기도제목, 2. 기도제목...',
                    value: AIIndicatorType.number,
                    groupValue: settings.indicatorType,
                    onChanged: (val) => ref.read(aiSettingsProvider.notifier).setIndicatorType(val!),
                  ),
                  _buildInnerDivider(),
                  _buildRadioTile(
                    title: '커스텀 기호',
                    subtitle: '지정한 기호를 머리말로 사용합니다.',
                    value: AIIndicatorType.custom,
                    groupValue: settings.indicatorType,
                    onChanged: (val) => ref.read(aiSettingsProvider.notifier).setIndicatorType(val!),
                  ),
                ],
              ),
            ),

            if (settings.indicatorType == AIIndicatorType.custom) ...[
              const SizedBox(height: 8),
              _buildTextFieldContainer(
                controller: _indicatorController,
                hint: '기호 입력 (예: 💖, ✨, -)',
                onApply: () {
                  final val = _indicatorController.text.trim();
                  if (val.isNotEmpty) {
                    ref.read(aiSettingsProvider.notifier).setCustomIndicator(val);
                    SnackBarUtil.showSnackBar(context, message: '커스텀 기호가 적용되었습니다.');
                  }
                },
              ),
            ],

            _buildDivider(),

            _buildSectionHeader('기도제목 말투 스타일', 'AI가 문장을 맺는 형식을 제안합니다.'),
            _buildSelectionContainer(
              child: Column(
                children: [
                  for (int i = 0; i < AIEndingStyle.values.length; i++) ...[
                    _buildRadioTile(
                      title: _getEndingStyleTitle(AIEndingStyle.values[i]),
                      value: AIEndingStyle.values[i],
                      groupValue: settings.endingStyle,
                      onChanged: (val) => ref.read(aiSettingsProvider.notifier).setEndingStyle(val!),
                    ),
                    if (i < AIEndingStyle.values.length - 1) _buildInnerDivider(),
                  ],
                ],
              ),
            ),

            if (settings.endingStyle == AIEndingStyle.custom) ...[
              const SizedBox(height: 8),
              _buildTextFieldContainer(
                controller: _endingController,
                hint: '예: ~하게 응답하소서',
                onApply: () {
                  final val = _endingController.text.trim();
                  if (val.isNotEmpty) {
                    ref.read(aiSettingsProvider.notifier).setCustomEndingStyle(val);
                    SnackBarUtil.showSnackBar(context, message: '커스텀 말투가 적용되었습니다.');
                  }
                },
              ),
            ],

            _buildDivider(),

            _buildSectionHeader('기도제목 공유 스타일', '카카오톡 공유 시 사용할 텍스트 포맷을 설정합니다.'),
            _buildSelectionContainer(
              child: _buildSwitchTile(
                title: '해당 주차 날짜 표시',
                subtitle: '제목 부분에 "1/18" 과 같이 날짜를 포함합니다.',
                value: settings.showDateInShare,
                onChanged: (val) => ref.read(aiSettingsProvider.notifier).setShowDateInShare(val),
              ),
            ),

            _buildDivider(),

            _buildSectionHeader('이름 양옆 기호 설정', '성도 이름 앞뒤에 붙을 아이콘을 지정하세요.'),
            _buildTextFieldContainer(
              controller: _shareIconController,
              hint: '아이콘 입력 (예: 💙, ✨)',
              onApply: () {
                final val = _shareIconController.text;
                ref.read(aiSettingsProvider.notifier).setShareHeaderIcon(val);
                SnackBarUtil.showSnackBar(context, message: val.isEmpty ? '공유 기호가 초기화되었습니다.' : '공유 기호가 적용되었습니다.');
              },
            ),

            const SizedBox(height: 48),
            _buildInfoCard(settings),
            
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
              fontFamily: 'Pretendard',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSub.withOpacity(0.7),
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Divider(color: AppTheme.border, thickness: 1),
    );
  }

  Widget _buildInnerDivider() {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16);
  }

  Widget _buildSelectionContainer({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildTextFieldContainer({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onApply,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'Pretendard', color: AppTheme.textMain),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: AppTheme.textSub.withOpacity(0.5), fontWeight: FontWeight.w500, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                isDense: true,
              ),
            ),
          ),
          TextButton(
            onPressed: onApply,
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.primaryViolet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('적용', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioTile<T>({
    required String title,
    String? subtitle,
    required T value,
    required T groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? AppTheme.primaryViolet : AppTheme.textMain,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSub.withOpacity(0.6), fontWeight: FontWeight.w400, fontFamily: 'Pretendard'),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.primaryViolet : const Color(0xFFE2E8F0),
                  width: isSelected ? 6 : 2,
                ),
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primaryViolet,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textMain, fontFamily: 'Pretendard'),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: AppTheme.textSub.withOpacity(0.6), fontFamily: 'Pretendard'),
      ),
    );
  }

  Widget _buildInfoCard(AISettings settings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primaryViolet.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryViolet.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primaryViolet, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '스타일 미리보기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryViolet, fontFamily: 'Pretendard'),
                ),
                const SizedBox(height: 6),
                Text(
                  '현재 설정에 맞춰 AI가 기도제목을 정돈해드립니다. ${settings.endingStyle == AIEndingStyle.custom ? "직접 입력하신 말투가 적용됩니다." : "선택하신 프리셋이 적용됩니다."}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.primaryViolet.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
