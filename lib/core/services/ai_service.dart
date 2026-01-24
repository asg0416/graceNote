import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/providers/settings_provider.dart';

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

  Future<List<String>> refinePrayers(List<String> rawPrayers, {AISettings? settings}) async {
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
        final url = 'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=${AppConstants.geminiApiKey}';
        print('AI 시도 중: $modelId... (JSON 모드)');

        final response = await http.post(
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
              'temperature': 0.2, // Lower temperature for stricter adherence to format
              'topK': 40,
              'topP': 0.95,
              'maxOutputTokens': 2048,
              'responseMimeType': 'application/json',
            }
          }),
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> body = jsonDecode(response.body);
          final String? text = body['candidates']?[0]?['content']?['parts']?[0]?['text'];

          if (text != null) {
            final dynamic decoded = jsonDecode(text);
            if (decoded is List) {
              final List<String> refined = decoded.map((e) => e.toString()).toList();
              
              // Ensure we have the same number of items
              if (refined.length == rawPrayers.length) {
                print('AI 성공: $modelId (${refined.length} 건)');
                return refined;
              } else {
                print('AI 개수 불일치: 입력 ${rawPrayers.length} vs 출력 ${refined.length}');
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
}
