// lib/core/providers/iam_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'package:grace_note/core/models/in_app_message.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';

part 'iam_provider.g.dart';

// ── 1. 서버에서 활성 메시지 스트림 ──────────────────────────────────

@riverpod
Stream<List<InAppMessage>> inAppMessages(InAppMessagesRef ref) {
  return Supabase.instance.client
      .from('in_app_messages')
      .stream(primaryKey: ['id'])
      .order('priority', ascending: false)
      .limit(20)
      .map((rows) => rows
          .map((r) => InAppMessage.fromJson(r))
          .where((m) => m.isCurrentlyActive)
          .toList());
}

// ── 2. 세션 내 임시 닫기 (앱 재진입 시 재표시됨) ─────────────────────

@riverpod
class IamSessionDismiss extends _$IamSessionDismiss {
  @override
  Set<String> build() => {};

  void dismiss(String messageId) {
    state = {...state, messageId};
  }
}

// ── 3. 영구·오늘그만보기 dismiss (SharedPreferences) ─────────────────

@riverpod
class IamDismissNotifier extends _$IamDismissNotifier {
  static const _prefix = 'iam_';

  @override
  Future<Map<String, String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)))
        key: prefs.getString(key)!,
    };
  }

  /// "오늘 그만보기" — 오늘 자정까지만 숨김
  Future<void> snoozeToday(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final key = '$_prefix$messageId';
    await prefs.setString(key, today);
    state = AsyncData({...?state.value, key: today});
  }

  /// "다시 보지 않기" — 영구 숨김 (재설치 전까지)
  Future<void> dismissPermanently(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    const value = 'dismissed';
    final key = '$_prefix$messageId';
    await prefs.setString(key, value);
    state = AsyncData({...?state.value, key: value});
  }
}

// ── 4. 실제 표시할 메시지 필터 ────────────────────────────────────────

@riverpod
List<InAppMessage> visibleIam(VisibleIamRef ref) {
  final messagesAsync    = ref.watch(inAppMessagesProvider);
  final dismissAsync     = ref.watch(iamDismissNotifierProvider);
  final sessionDismissed = ref.watch(iamSessionDismissProvider);
  final userRole         = ref.watch(activeRoleProvider);

  final messages     = messagesAsync.value ?? [];
  final persistState = dismissAsync.value ?? {};
  final today        = DateFormat('yyyy-MM-dd').format(DateTime.now());

  return messages.where((m) {
    // 1. 세션 내 닫기 체크
    if (sessionDismissed.contains(m.id)) return false;

    // 2. 영구 dismiss / 오늘 그만보기 체크
    final stored = persistState['iam_${m.id}'];
    if (stored == 'dismissed') return false;
    if (stored == today)       return false;

    // 3. 역할 필터 (null-safe)
    if (userRole != null && m.targetRole != IamTargetRole.all) {
      if (m.targetRole == IamTargetRole.leader && userRole != AppRole.leader) return false;
      if (m.targetRole == IamTargetRole.member && userRole != AppRole.member) return false;
    }

    return true;
  }).toList();
}

// ── 5. survey 이미 응답 여부 확인 ────────────────────────────────────

@riverpod
Future<bool> iamSurveyAnswered(
  IamSurveyAnsweredRef ref,
  String messageId,
) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return false;

  final res = await Supabase.instance.client
      .from('iam_survey_responses')
      .select('id')
      .eq('message_id', messageId)
      .eq('user_id', userId)
      .maybeSingle();

  return res != null;
}
