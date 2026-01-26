import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
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


  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('서비스 설정'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopHero(),
            const SizedBox(height: 32),

            _buildSectionHeader('기도제목 구분 스타일', '항목을 나눌 때 사용할 기호를 선택하세요.'),
            const SizedBox(height: 12),
            _buildCard(
              child: Column(
                children: [
                  _buildRadioTile(
                    title: '번호 매기기',
                    subtitle: '1. 기도제목, 2. 기도제목...',
                    value: AIIndicatorType.number,
                    groupValue: settings.indicatorType,
                    onChanged: (val) => ref.read(aiSettingsProvider.notifier).setIndicatorType(val!),
                  ),
                  _buildDivider(),
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
              const SizedBox(height: 16),
              _buildCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _indicatorController,
                        decoration: const InputDecoration(
                          hintText: '기호 입력 (예: 💖, ✨, -)',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                    _buildApplyButton(onPressed: () {
                      final val = _indicatorController.text.trim();
                      if (val.isNotEmpty) {
                        ref.read(aiSettingsProvider.notifier).setCustomIndicator(val);
                        SnackBarUtil.showSnackBar(context, message: '커스텀 기호가 적용되었습니다.');
                      }
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),
            _buildSectionHeader('기도제목 말투 스타일', 'AI가 문장을 맺는 형식을 제안합니다.'),
            const SizedBox(height: 12),
            _buildCard(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: AIEndingStyle.values.length,
                separatorBuilder: (context, index) => _buildDivider(),
                itemBuilder: (context, index) {
                  final style = AIEndingStyle.values[index];
                  String title = '';
                  switch (style) {
                    case AIEndingStyle.pray: title = '~하기를 기도합니다'; break;
                    case AIEndingStyle.desire: title = '~하기를 소망합니다'; break;
                    case AIEndingStyle.wish: title = '~하길 원합니다'; break;
                    case AIEndingStyle.to: title = '~하도록 (개조식)'; break;
                    case AIEndingStyle.doing: title = '~하기를'; break;
                    case AIEndingStyle.simple: title = '~하기'; break;
                    case AIEndingStyle.custom: title = '직접 입력'; break;
                  }
                  return _buildRadioTile(
                    title: title,
                    value: style,
                    groupValue: settings.endingStyle,
                    onChanged: (val) => ref.read(aiSettingsProvider.notifier).setEndingStyle(val!),
                  );
                },
              ),
            ),

            if (settings.endingStyle == AIEndingStyle.custom) ...[
              const SizedBox(height: 16),
              _buildCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _endingController,
                        decoration: const InputDecoration(
                          hintText: '예: ~하게 응답하소서',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                    _buildApplyButton(onPressed: () {
                      final val = _endingController.text.trim();
                      if (val.isNotEmpty) {
                        ref.read(aiSettingsProvider.notifier).setCustomEndingStyle(val);
                        SnackBarUtil.showSnackBar(context, message: '커스텀 말투가 적용되었습니다.');
                      }
                    }),
                  ],
                ),
              ),
            ],

            _buildSectionHeader('기도제목 공유 스타일', '카카오톡 공유 시 사용할 텍스트 포맷을 설정합니다.'),
            const SizedBox(height: 12),
            _buildCard(
              child: _buildSwitchTile(
                title: '해당 주차 날짜 표시',
                subtitle: '제목 부분에 "1/18" 과 같이 날짜를 포함합니다.',
                value: settings.showDateInShare,
                onChanged: (val) => ref.read(aiSettingsProvider.notifier).setShowDateInShare(val),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('이름 양옆 기호 설정', '성도 이름 앞뒤에 붙을 아이콘을 지정하세요.'),
            const SizedBox(height: 12),
            _buildCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _shareIconController,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        hintText: '아이콘 입력 (예: 💙, ✨)',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                  _buildApplyButton(onPressed: () {
                    // 빈 문자열인 경우에도 저장을 허용하여 '삭제' 기능 지원
                    final val = _shareIconController.text;
                    ref.read(aiSettingsProvider.notifier).setShareHeaderIcon(val);
                    SnackBarUtil.showSnackBar(context, message: val.isEmpty ? '공유 기호가 초기화되었습니다.' : '공유 기호가 적용되었습니다.');
                  }),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildInfoCard(settings),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryIndigo, size: 24),
            ),
            const SizedBox(width: 16),
            const Text(
              'AI 정리 설정',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textMain, letterSpacing: -0.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '조원들의 기도제목을 더 깔끔하고 정성스럽게\n정돈하기 위한 나만의 스타일을 만들어보세요.',
          style: TextStyle(fontSize: 15, color: AppTheme.textSub, height: 1.5, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textMain)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.textLight, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.divider.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      color: isSelected ? AppTheme.primaryIndigo : AppTheme.textMain,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSub, fontWeight: FontWeight.w400),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.primaryIndigo : AppTheme.divider,
                  width: isSelected ? 7 : 2,
                ),
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, color: AppTheme.divider.withOpacity(0.5), indent: 20, endIndent: 20);
  }

  Widget _buildApplyButton({required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        backgroundColor: AppTheme.primaryIndigo,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: const Text('적용', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSub, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          if (trailing != null) 
            trailing
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primaryIndigo,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(AISettings settings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryIndigo.withOpacity(0.08),
            AppTheme.primaryIndigo.withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primaryIndigo.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primaryIndigo, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '스타일 미리보기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryIndigo),
                ),
                const SizedBox(height: 6),
                Text(
                  '현재 설정에 맞춰 AI가 기도제목을 정돈해드립니다. ${settings.endingStyle == AIEndingStyle.custom ? "직접 입력하신 말투가 적용됩니다." : "선택하신 프리셋이 적용됩니다."}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.primaryIndigo.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
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
