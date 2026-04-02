import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/providers/data_providers.dart';

enum AIIndicatorType {
  number,
  custom
}

enum AIEndingStyle {
  pray,      // ~하기를 기도합니다
  desire,    // ~하기를 소망합니다
  wish,      // ~하길 원합니다
  to,        // ~하도록
  doing,     // ~하기를
  simple,    // ~하기
  custom     // 직접 입력
}

class AISettings {
  final AIIndicatorType indicatorType;
  final String customIndicator;
  final AIEndingStyle endingStyle;
  final bool showDateInShare;
  final bool showFamilyInShare;
  final String shareHeaderIcon; // 예: 🩵, ✨, 📋
  final String customEndingStyle;
  final bool alwaysGroupFamily;

  AISettings({
    this.indicatorType = AIIndicatorType.number,
    this.customIndicator = '🌱',
    AIEndingStyle? endingStyle,
    this.showDateInShare = true,
    this.showFamilyInShare = true,
    this.shareHeaderIcon = '❤️',
    this.customEndingStyle = '',
    this.alwaysGroupFamily = false,
  }) : endingStyle = endingStyle ?? AIEndingStyle.pray;

  AISettings copyWith({
    AIIndicatorType? indicatorType,
    String? customIndicator,
    AIEndingStyle? endingStyle,
    bool? showDateInShare,
    bool? showFamilyInShare,
    String? shareHeaderIcon,
    String? customEndingStyle,
    bool? alwaysGroupFamily,
  }) {
    return AISettings(
      indicatorType: indicatorType ?? this.indicatorType,
      customIndicator: customIndicator ?? this.customIndicator,
      endingStyle: endingStyle ?? this.endingStyle,
      showDateInShare: showDateInShare ?? this.showDateInShare,
      showFamilyInShare: showFamilyInShare ?? this.showFamilyInShare,
      shareHeaderIcon: shareHeaderIcon ?? this.shareHeaderIcon,
      customEndingStyle: customEndingStyle ?? this.customEndingStyle,
      alwaysGroupFamily: alwaysGroupFamily ?? this.alwaysGroupFamily,
    );
  }
}

class AISettingsNotifier extends StateNotifier<AISettings> {
  final SharedPreferences _prefs;
  final String? _userId;

  AISettingsNotifier(this._prefs, this._userId) : super(AISettings()) {
    _loadSettings();
  }

  String _getKey(String key) {
    if (_userId == null) return key;
    return 'user_${_userId}_$key';
  }

  void _loadSettings() {
    final typeIndex = _prefs.getInt(_getKey('ai_indicator_type')) ?? 0;
    final customIndicator = _prefs.getString(_getKey('ai_custom_indicator')) ?? '🌱';
    final endingStyleIndex = _prefs.getInt(_getKey('ai_ending_style')) ?? 0;
    final customEndingStyle = _prefs.getString(_getKey('ai_custom_ending_style')) ?? '';
    final showDateInShare = _prefs.getBool(_getKey('share_show_date')) ?? true;
    final showFamilyInShare = _prefs.getBool(_getKey('share_show_family')) ?? true;
    final shareHeaderIcon = _prefs.getString(_getKey('share_header_icon')) ?? '❤️';
    final alwaysGroupFamily = _prefs.getBool(_getKey('share_always_group_family')) ?? false;

    state = AISettings(
      indicatorType: AIIndicatorType.values[typeIndex],
      customIndicator: customIndicator,
      endingStyle: AIEndingStyle.values[endingStyleIndex < AIEndingStyle.values.length ? endingStyleIndex : 0],
      customEndingStyle: customEndingStyle,
      showDateInShare: showDateInShare,
      showFamilyInShare: showFamilyInShare,
      shareHeaderIcon: shareHeaderIcon,
      alwaysGroupFamily: alwaysGroupFamily,
    );
  }

  Future<void> setShowDateInShare(bool value) async {
    await _prefs.setBool(_getKey('share_show_date'), value);
    state = state.copyWith(showDateInShare: value);
  }

  Future<void> setShowFamilyInShare(bool value) async {
    await _prefs.setBool(_getKey('share_show_family'), value);
    state = state.copyWith(showFamilyInShare: value);
  }

  Future<void> setShareHeaderIcon(String icon) async {
    await _prefs.setString(_getKey('share_header_icon'), icon);
    state = state.copyWith(shareHeaderIcon: icon);
  }

  Future<void> setAlwaysGroupFamily(bool value) async {
    await _prefs.setBool(_getKey('share_always_group_family'), value);
    state = state.copyWith(alwaysGroupFamily: value);
  }

  Future<void> setIndicatorType(AIIndicatorType type) async {
    await _prefs.setInt(_getKey('ai_indicator_type'), type.index);
    state = state.copyWith(indicatorType: type);
  }

  Future<void> setCustomIndicator(String indicator) async {
    await _prefs.setString(_getKey('ai_custom_indicator'), indicator);
    state = state.copyWith(customIndicator: indicator);
  }

  Future<void> setEndingStyle(AIEndingStyle style) async {
    await _prefs.setInt(_getKey('ai_ending_style'), style.index);
    state = state.copyWith(endingStyle: style);
  }

  Future<void> setCustomEndingStyle(String style) async {
    await _prefs.setString(_getKey('ai_custom_ending_style'), style);
    state = state.copyWith(customEndingStyle: style);
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final aiSettingsProvider = StateNotifierProvider<AISettingsNotifier, AISettings>((ref) {
  // Rebuild on auth changes
  ref.watch(authStateProvider);
  
  final prefs = ref.watch(sharedPreferencesProvider);
  final userId = Supabase.instance.client.auth.currentUser?.id;
  return AISettingsNotifier(prefs, userId);
});
