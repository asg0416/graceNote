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

    test('자녀 기도제목을 부모 두 사람에게 공통으로 합친다', () {
      final response = jsonEncode({
        'matches': [
          {'name': '김다정', 'prayer': '새로 발령 받은 곳에서 업무를 잘 배우도록'},
          {'name': '김보성', 'prayer': '더운 여름을 안전하게 보내도록'},
          {
            'name': '김다정',
            'prayer': '(수안하늘) 방학 동안 돌봄과 오고 가는 길이 안전하도록',
          },
          {
            'name': '김보성',
            'prayer': '(수안하늘) 방학 동안 돌봄과 오고 가는 길이 안전하도록',
          },
        ],
      });

      final result = AIService.decodePrayerMemoOutput(
        response,
        ['김보성', '김다정'],
      );

      expect(
        result['김다정'],
        '새로 발령 받은 곳에서 업무를 잘 배우도록\n'
        '(수안하늘) 방학 동안 돌봄과 오고 가는 길이 안전하도록',
      );
      expect(
        result['김보성'],
        '더운 여름을 안전하게 보내도록\n'
        '(수안하늘) 방학 동안 돌봄과 오고 가는 길이 안전하도록',
      );
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
