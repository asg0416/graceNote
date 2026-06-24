import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/features/admin/presentation/widgets/effective_week_picker_field.dart';

void main() {
  testWidgets('renders without a surrounding Material ancestor',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: EffectiveWeekPickerField(
          effectiveWeekDate: DateTime(2026, 6, 21),
          enabled: true,
          onTap: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('2026. 6. 21.'), findsOneWidget);
    expect(find.text('이 주차부터 반영'), findsOneWidget);
  });
}
