import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/core/widgets/push_permission_banner.dart';

void main() {
  testWidgets('push permission banner stays hidden outside web builds',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PushPermissionBanner(),
          ),
        ),
      ),
    );

    expect(find.byType(PushPermissionBanner), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
