import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/features/admin/presentation/widgets/move_group_effective_week.dart';

void main() {
  test('clamps move week to the current season start', () {
    final result = resolveMoveEffectiveWeek(
      requestedWeek: DateTime(2026, 6, 7),
      seasonStartWeek: DateTime(2026, 6, 14),
      seasonEndWeek: DateTime(2026, 12, 27),
    );

    expect(result, DateTime(2026, 6, 14));
  });

  test('keeps a requested week inside the current season', () {
    final result = resolveMoveEffectiveWeek(
      requestedWeek: DateTime(2026, 6, 21),
      seasonStartWeek: DateTime(2026, 6, 14),
      seasonEndWeek: DateTime(2026, 12, 27),
    );

    expect(result, DateTime(2026, 6, 21));
  });

  test('clamps move week to the current season end', () {
    final result = resolveMoveEffectiveWeek(
      requestedWeek: DateTime(2027, 1, 3),
      seasonStartWeek: DateTime(2026, 6, 14),
      seasonEndWeek: DateTime(2026, 12, 27),
    );

    expect(result, DateTime(2026, 12, 27));
  });

  test('clamps a future move week to the current week', () {
    final result = resolveMoveEffectiveWeek(
      requestedWeek: DateTime(2026, 7, 5),
      seasonStartWeek: DateTime(2026, 6, 14),
      seasonEndWeek: DateTime(2026, 12, 27),
      currentWeek: DateTime(2026, 6, 21),
    );

    expect(result, DateTime(2026, 6, 21));
  });
}
