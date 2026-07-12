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

  // Target models discovered from ListModels output for this key in 2026
  final List<String> _modelIds = [
    'gemini-2.0-flash',
    'gemini-2.5-flash',
    'gemini-flash-latest',
    'gemini-pro-latest',
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
2. 매칭이 불확실하면 빈 문자열("")로 두고 억지로 매칭하지 마세요.
3. 반드시 아래 JSON 형식으로만 응답하세요. 설명 문장은 절대 추가하지 마세요.
   형식: {"조원이름_전체": "기도제목 내용", ...}
4. 반환하는 키(이름)는 반드시 조원 명단에 있는 정확한 이름을 사용하세요.
5. 기도제목은 원문의 표현을 최대한 그대로 보존하세요. 다듬거나 변경하지 마세요.
6. 명단에 없는 이름은 결과에 포함하지 마세요.

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

        final dynamic decoded;
        try {
          decoded = jsonDecode(text);
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
            errorType: 'model_output_json',
            errorMessage: e.toString(),
          );
          lastError = e;
          continue;
        }

        if (decoded is Map) {
          // 키가 실제 명단에 있는 이름인 것만 필터링
          final result = <String, String>{};
          for (final entry in decoded.entries) {
            final name = entry.key.toString();
            if (memberNames.contains(name)) {
              result[name] = entry.value?.toString() ?? '';
            }
          }
          if (result.isNotEmpty) {
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
              matchedCount: result.length,
            );
            print('메모 파싱 성공: $modelId (${result.length}명 매칭)');
            return result;
          }

          await _writeMemoDiagnostic(
            requestId: requestId,
            churchId: churchId,
            groupId: groupId,
            modelId: modelId,
            attemptNo: index + 1,
            outcome: 'invalid_result',
            statusCode: response.statusCode,
            durationMs: stopwatch.elapsedMilliseconds,
            inputChars: memoText.length,
            memberCount: memberNames.length,
            matchedCount: 0,
            errorType: 'no_member_name_matched',
            errorMessage: 'JSON object returned, but no member name matched',
          );
          lastError = 'No member name matched';
          continue;
        }

        await _writeMemoDiagnostic(
          requestId: requestId,
          churchId: churchId,
          groupId: groupId,
          modelId: modelId,
          attemptNo: index + 1,
          outcome: 'invalid_result',
          statusCode: response.statusCode,
          durationMs: stopwatch.elapsedMilliseconds,
          inputChars: memoText.length,
          memberCount: memberNames.length,
          errorType: 'model_output_not_object',
          errorMessage: 'Model output was not a JSON object',
        );
        lastError = 'Model output was not a JSON object';
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
