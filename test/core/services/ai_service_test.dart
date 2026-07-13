import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/core/services/ai_service.dart';

void main() {
  group('AIService.decodePrayerMemoOutput', () {
    test('같은 기도제목으로 연결된 여러 실제 조원을 각각 매칭한다', () {
      final response = jsonEncode({
        'matches': [
          {'name': '이세형', 'prayer': '가족의 건강'},
          {'name': '김영은', 'prayer': '가족의 건강'},
        ],
      });

      final result = AIService.decodePrayerMemoOutput(
        response,
        ['이세형', '김영은', '김보성'],
      );

      expect(result, {
        '이세형': '가족의 건강',
        '김영은': '가족의 건강',
        '김보성': '',
      });
    });

    test('유효한 0명 매칭은 실패가 아니라 빈 기도제목 결과로 반환한다', () {
      final result = AIService.decodePrayerMemoOutput(
        '{"matches": []}',
        ['올리브새가족조장', '올리브새가족조원'],
      );

      expect(result, {
        '올리브새가족조장': '',
        '올리브새가족조원': '',
      });
    });

    test('같은 조원의 여러 기도제목은 유실하지 않고 합친다', () {
      final response = jsonEncode({
        'matches': [
          {'name': '이세형', 'prayer': '가족의 건강'},
          {'name': '이세형', 'prayer': '직장 일정'},
        ],
      });

      final result = AIService.decodePrayerMemoOutput(response, ['이세형']);

      expect(result['이세형'], '가족의 건강\n직장 일정');
    });

    test('형식이 깨진 JSON은 재시도할 수 있도록 예외를 발생시킨다', () {
      expect(
        () => AIService.decodePrayerMemoOutput(
          '{"matches": [{"name": "이세형"',
          ['이세형'],
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
