import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  // Use explicit stable model IDs so production behavior does not change when
  // a `latest` alias is moved to another model.
  static const List<String> _modelIds = [
    'gemini-3.5-flash',
    'gemini-2.5-flash',
  ];

  void init() {}

  Future<List<String>> refinePrayers(List<String> rawPrayers,
      {AISettings? settings}) async {
    if (rawPrayers.isEmpty) return [];

    final indicatorStr = settings?.indicatorType == AIIndicatorType.custom
        ? '각 기도제목 항목(주제)마다 "${settings?.customIndicator ?? '💖'}" 기호를 앞에 붙이고 줄바꿈하세요.'
        : '각 기도제목 항목(주제)마다 "1.", "2."와 같이 번호를 매기고 줄바꿈하세요.';

    String endingStyleStr;
    final style = settings?.endingStyle ?? AIEndingStyle.pray;
    switch (style) {
      case AIEndingStyle.pray:
        endingStyleStr = '"~하기를 기도합니다"';
        break;
      case AIEndingStyle.desire:
        endingStyleStr = '"~하기를 소망합니다"';
        break;
      case AIEndingStyle.wish:
        endingStyleStr = '"~하길 원합니다"';
        break;
      case AIEndingStyle.to:
        endingStyleStr = '"~하도록"';
        break;
      case AIEndingStyle.doing:
        endingStyleStr = '"~하기를"';
        break;
      case AIEndingStyle.simple:
        endingStyleStr = '"~하기"';
        break;
      case AIEndingStyle.custom:
        endingStyleStr = '"${settings?.customEndingStyle ?? '~하기를 기도합니다'}"';
        break;
    }

    final prompt = '''
당신은 기독교 소그룹의 기도제목을 정리해주는 도우미입니다. 
입력된 리스트의 각 항목을 아래 규칙에 따라 정중하고 부드럽게 다듬어주세요.

**절대 엄수 규칙 (어길 경우 오류로 간주함)**:
1. **말투**: 문장의 끝(종결 어미)을 반드시 $endingStyleStr 스타일로 통일하세요.
   - 예외 없이 모든 문항을 이 말투로 끝맺음합니다.
   - (이미 정해진 예전 기독교 문체인 "~하소서", "~하게 하소서" 등은 사용자가 명시적으로 요청하지 않는 한 피하십시오.)
2. **형식**: 반드시 JSON 배열 형식으로만 응답하세요. (예: ["정리내용1", "정리내용2", ...])
3. **인디케이터**: $indicatorStr 
   - 한 사람의 입력에 여러 주제(예: 건강, 이직 등)가 섞여 있다면, **반드시 개별 주제마다** 기호/번호를 붙여서 구분하세요.
4. **내용 보존**: 입력된 모든 단어와 취지를 생략 없이 포함하세요.
5. **매칭**: 입력된 리스트의 개수(${rawPrayers.length}개)와 출력되는 JSON 배열의 개수가 반드시 일치해야 합니다.

입력 리스트:
${jsonEncode(rawPrayers)}
''';

    Object? lastError;

    for (final modelId in _modelIds) {
      try {
        final url =
            'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=${AppConstants.geminiApiKey}';
        print('AI 시도 중: $modelId... (JSON 모드)');

        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt}
                    ]
                  }
                ],
                'generationConfig': {
                  'temperature':
                      0.2, // Lower temperature for stricter adherence to format
                  'topK': 40,
                  'topP': 0.95,
                  'maxOutputTokens': 2048,
                  'responseMimeType': 'application/json',
                  'responseSchema': {
                    'type': 'ARRAY',
                    'items': {'type': 'STRING'},
                  },
                  'thinkingConfig': _thinkingConfigFor(modelId),
                }
              }),
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          final Map<String, dynamic> body = jsonDecode(response.body);
          final String? text =
              body['candidates']?[0]?['content']?['parts']?[0]?['text'];

          if (text != null) {
            final dynamic decoded = jsonDecode(text);
            if (decoded is List) {
              final List<String> refined =
                  decoded.map((e) => e.toString()).toList();

              // Ensure we have the same number of items
              if (refined.length == rawPrayers.length) {
                print('AI 성공: $modelId (${refined.length} 건)');
                return refined;
              } else {
                print(
                    'AI 개수 불일치: 입력 ${rawPrayers.length} vs 출력 ${refined.length}');
                lastError = 'Count mismatch';
              }
            }
          }
        }

        lastError = 'Status ${response.statusCode}: ${response.body}';
        print('AI $modelId 실패: $lastError');
      } catch (e) {
        print('AI $modelId 에러: $e');
        lastError = e;
      }
    }

    print('모든 AI 시도 실패. 최종 에러: $lastError');
    return rawPrayers;
  }

  /// 자유형식 메모에서 이름-기도제목 쌍을 추출합니다.
  /// [memoText]: 조장이 붙여넣은 원본 메모
  /// [memberNames]: 현재 조원 이름 목록 (매칭 기준)
  /// 반환값: {"조원 전체 이름": "기도제목"} 형태의 Map, 실패 시 빈 Map
  Future<Map<String, String>> parsePrayerMemo(
      String memoText, List<String> memberNames,
      {String? churchId, String? groupId}) async {
    if (memoText.trim().isEmpty || memberNames.isEmpty) return {};

    final prompt = '''
당신은 소그룹 모임 기도제목 메모를 분석하는 도우미입니다.

조원 명단: ${jsonEncode(memberNames)}

아래 메모에서 각 조원의 이름과 기도제목을 찾아 매칭해 주세요.

규칙:
1. 이름이 일부만 쓰였거나 (예: "진슬" → "임진슬"), 성 없이 이름만 있어도 명단에서 가장 가까운 이름과 매칭하세요.
2. 메모는 가족 단위 블록으로 작성될 수 있습니다. 블록 제목에는 하트 기호 뒤에 실제 조원 이름 한 명 이상이 함께 표시될 수 있습니다.
3. 두 명 이상의 실제 조원 이름이 구분자 없이 연속으로 붙어 있을 수 있습니다.
   예: "이세형김영은"은 "이세형", "김영은" 두 사람이며, 이어지는 기도제목을 두 사람 모두에게 동일하게 매칭하세요.
4. 하위 항목의 괄호 안 이름이 조원 명단에 있으면 그 조원에게만 매칭하세요.
5. 하위 항목의 괄호 안 이름이 명단에 없지만 자녀나 가족 이름으로 보이면 해당 항목을 버리지 마세요.
   가장 가까운 앞쪽 블록 제목에 표시된 실제 조원 전원에게 같은 기도제목을 각각 매칭하세요.
   이때 명단에 없는 가족 이름은 name 필드에 사용하지 말고 prayer 문자열 안에 원문 그대로 남기세요.
6. 이 가족 공동 배정 규칙은 앞쪽 블록 제목에서 실제 조원 이름이 명확하게 확인될 때만 적용하세요.
   귀속할 블록을 확인할 수 없으면 억지로 매칭하지 말고 생략하세요.
7. 하나의 조원에게 본인 항목과 가족 항목이 모두 있으면 matches에 같은 name을 여러 번 반환해도 됩니다.
   각 기도 항목은 별도의 match로 반환하세요.
8. 예를 들어 블록 제목이 "김보성김다정"이고 하위 항목이 "(수안하늘) 방학 동안 돌봄과 오고 가는 길의 안전"이라면,
   그 항목을 김보성과 김다정에게 각각 한 번씩 배정하고 prayer에는 "(수안하늘)"을 포함하세요.
9. 반드시 아래 JSON 형식으로만 응답하세요. 설명 문장은 절대 추가하지 마세요.
   형식: {"matches": [{"name": "조원이름_전체", "prayer": "기도제목 내용"}]}
   메모에서 기도제목을 찾지 못한 조원은 matches 배열에서 생략하세요.
10. name은 반드시 조원 명단에 있는 정확한 이름을 사용하세요.
11. 기도제목은 원문의 표현을 최대한 그대로 보존하세요. 다듬거나 변경하지 마세요.
12. 명단에 없는 이름은 name 필드에 포함하지 마세요.

메모 내용:
$memoText
''';

    Object? lastError;
    final requestId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();

    for (var index = 0; index < _modelIds.length; index++) {
      final modelId = _modelIds[index];
      final stopwatch = Stopwatch()..start();
      try {
        final url =
            'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=${AppConstants.geminiApiKey}';
        print('메모 파싱 AI 시도 중: $modelId...');

        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt}
                    ]
                  }
                ],
                'generationConfig': {
                  'temperature': 0.1,
                  'topK': 40,
                  'topP': 0.95,
                  'maxOutputTokens': 4096,
                  'responseMimeType': 'application/json',
                  'responseSchema': _prayerMemoResponseSchema(memberNames),
                  'thinkingConfig': _thinkingConfigFor(modelId),
                }
              }),
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode != 200) {
          final errorMessage = _summarizeProviderError(response.body);
          await _writeMemoDiagnostic(
            requestId: requestId,
            churchId: churchId,
            groupId: groupId,
            modelId: modelId,
            attemptNo: index + 1,
            outcome: 'http_error',
            statusCode: response.statusCode,
            durationMs: stopwatch.elapsedMilliseconds,
            inputChars: memoText.length,
            memberCount: memberNames.length,
            errorType: 'http_${response.statusCode}',
            errorMessage: errorMessage,
          );
          print('메모 파싱 $modelId 실패: HTTP ${response.statusCode}');
          lastError = 'Status ${response.statusCode}: $errorMessage';
          continue;
        }

        final Map<String, dynamic> body;
        try {
          body = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e) {
          await _writeMemoDiagnostic(
            requestId: requestId,
            churchId: churchId,
            groupId: groupId,
            modelId: modelId,
            attemptNo: index + 1,
            outcome: 'json_parse_error',
            statusCode: response.statusCode,
            durationMs: stopwatch.elapsedMilliseconds,
            inputChars: memoText.length,
            memberCount: memberNames.length,
            errorType: 'provider_response_json',
            errorMessage: e.toString(),
          );
          lastError = e;
          continue;
        }

        final String? text =
            body['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (text == null || text.trim().isEmpty) {
          final candidates = body['candidates'];
          final firstCandidate = candidates is List && candidates.isNotEmpty
              ? candidates.first
              : null;
          await _writeMemoDiagnostic(
            requestId: requestId,
            churchId: churchId,
            groupId: groupId,
            modelId: modelId,
            attemptNo: index + 1,
            outcome: 'provider_empty',
            statusCode: response.statusCode,
            durationMs: stopwatch.elapsedMilliseconds,
            inputChars: memoText.length,
            memberCount: memberNames.length,
            errorType: body['promptFeedback'] != null
                ? 'prompt_feedback'
                : 'no_candidate_text',
            errorMessage: _summarizeProviderError(jsonEncode({
              'promptFeedback': body['promptFeedback'],
              'finishReason':
                  firstCandidate is Map ? firstCandidate['finishReason'] : null,
            })),
          );
          lastError = 'Provider returned no candidate text';
          continue;
        }

        final Map<String, String> result;
        try {
          result = decodePrayerMemoOutput(text, memberNames);
        } catch (e) {
          final candidates = body['candidates'];
          final firstCandidate = candidates is List && candidates.isNotEmpty
              ? candidates.first
              : null;
          final finishReason =
              firstCandidate is Map ? firstCandidate['finishReason'] : null;
          await _writeMemoDiagnostic(
            requestId: requestId,
            churchId: churchId,
            groupId: groupId,
            modelId: modelId,
            attemptNo: index + 1,
            outcome: 'json_parse_error',
            statusCode: response.statusCode,
            durationMs: stopwatch.elapsedMilliseconds,
            inputChars: memoText.length,
            memberCount: memberNames.length,
            errorType: 'model_output_json',
            errorMessage:
                '$e; finishReason=$finishReason; outputChars=${text.length}',
          );
          lastError = e;
          continue;
        }

        final matchedCount =
            result.values.where((value) => value.trim().isNotEmpty).length;
        await _writeMemoDiagnostic(
          requestId: requestId,
          churchId: churchId,
          groupId: groupId,
          modelId: modelId,
          attemptNo: index + 1,
          outcome: 'success',
          statusCode: response.statusCode,
          durationMs: stopwatch.elapsedMilliseconds,
          inputChars: memoText.length,
          memberCount: memberNames.length,
          matchedCount: matchedCount,
        );
        print('메모 파싱 성공: $modelId ($matchedCount명 매칭)');
        return result;
      } catch (e) {
        await _writeMemoDiagnostic(
          requestId: requestId,
          churchId: churchId,
          groupId: groupId,
          modelId: modelId,
          attemptNo: index + 1,
          outcome: 'exception',
          durationMs: stopwatch.elapsedMilliseconds,
          inputChars: memoText.length,
          memberCount: memberNames.length,
          errorType: e.runtimeType.toString(),
          errorMessage: e.toString(),
        );
        print('메모 파싱 $modelId 에러: $e');
        lastError = e;
      } finally {
        stopwatch.stop();
      }
    }

    print('메모 파싱 모든 시도 실패. 최종 에러: $lastError');
    return {};
  }

  static Map<String, dynamic> _thinkingConfigFor(String modelId) {
    if (modelId.startsWith('gemini-3')) {
      return {'thinkingLevel': 'minimal'};
    }
    return {'thinkingBudget': 0};
  }

  static Map<String, dynamic> _prayerMemoResponseSchema(
      List<String> memberNames) {
    final uniqueNames = memberNames.toSet().toList(growable: false);
    return {
      'type': 'OBJECT',
      'properties': {
        'matches': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'name': {
                'type': 'STRING',
                'enum': uniqueNames,
              },
              'prayer': {
                'type': 'STRING',
                'description': '원문 표현을 보존한 해당 조원의 기도제목',
              },
            },
            'required': ['name', 'prayer'],
          },
        },
      },
      'required': ['matches'],
    };
  }

  /// Decodes and validates the structured memo response.
  ///
  /// Every roster member is included in the returned map. Members that were
  /// not matched have an empty prayer so the UI can show "매칭 안됨" instead
  /// of treating a valid zero-match response as a provider failure.
  static Map<String, String> decodePrayerMemoOutput(
      String responseText, List<String> memberNames) {
    final decoded = jsonDecode(responseText);
    if (decoded is! Map || decoded['matches'] is! List) {
      throw const FormatException('Expected an object containing matches');
    }

    final uniqueNames = memberNames.toSet().toList(growable: false);
    final result = <String, String>{
      for (final name in uniqueNames) name: '',
    };

    for (final item in decoded['matches'] as List) {
      if (item is! Map ||
          item['name'] is! String ||
          item['prayer'] is! String) {
        throw const FormatException('Each match must contain name and prayer');
      }

      final name = item['name'] as String;
      final prayer = (item['prayer'] as String).trim();
      if (!result.containsKey(name) || prayer.isEmpty) continue;

      final existing = result[name]!;
      if (existing.isEmpty) {
        result[name] = prayer;
      } else if (existing != prayer) {
        result[name] = '$existing\n$prayer';
      }
    }

    return result;
  }

  String _summarizeProviderError(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 500) return normalized;
    return normalized.substring(0, 500);
  }

  Future<void> _writeMemoDiagnostic({
    required String requestId,
    required String? churchId,
    required String? groupId,
    required String modelId,
    required int attemptNo,
    required String outcome,
    int? statusCode,
    required int durationMs,
    required int inputChars,
    required int memberCount,
    int? matchedCount,
    String? errorType,
    String? errorMessage,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client.from('ai_request_logs').insert({
        'request_id': requestId,
        'user_id': userId,
        'church_id': churchId,
        'group_id': groupId,
        'feature': 'parse_prayer_memo',
        'model_id': modelId,
        'attempt_no': attemptNo,
        'outcome': outcome,
        'status_code': statusCode,
        'duration_ms': durationMs,
        'input_chars': inputChars,
        'member_count': memberCount,
        'matched_count': matchedCount,
        'error_type': errorType,
        'error_message':
            errorMessage == null ? null : _summarizeProviderError(errorMessage),
        'app_version': AppConstants.appVersion,
      });
    } catch (e) {
      // Diagnostics must never change the user-facing AI flow.
      print('AI 진단 로그 저장 실패: $e');
    }
  }
}
