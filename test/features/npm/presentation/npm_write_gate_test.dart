import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_write_gate.dart';

Widget _app({required NpmAccount? account, required VoidCallback onPressed}) {
  return ProviderScope(
    overrides: [npmAccountProvider.overrideWith((ref) async => account)],
    child: MaterialApp(
      home: Scaffold(
        body: NpmWriteButton(
          resource: NpmResource.certificates,
          label: 'Renew',
          onPressed: onPressed,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a write this account cannot make stays reachable and answers', (
    tester,
  ) async {
    var ran = false;
    await tester.pumpWidget(
      _app(
        account: const NpmAccount(
          id: 1,
          name: 'Reader',
          isAdmin: false,
          permissions: {'certificates': 'view'},
        ),
        onPressed: () => ran = true,
      ),
    );
    await tester.pumpAndSettle();

    // Still on screen, still named — hiding the control would hide the fact.
    final button = find.widgetWithText(TextButton, 'Renew');
    expect(button, findsOneWidget);
    // Still tappable: `onPressed: null` would take it off the screen reader's
    // path as well as off the pointer's, which is the whole point of the rule.
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    expect(
      tester.getSemantics(find.byType(NpmWriteButton)).hint.contains('admin'),
      isTrue,
      reason: 'the reason has to be spoken, not only greyed',
    );

    await tester.tap(button);
    await tester.pump();

    // It answers instead of acting.
    expect(ran, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('an admin gets the plain control with no hint', (tester) async {
    var ran = false;
    await tester.pumpWidget(
      _app(
        account: const NpmAccount(
          id: 1,
          name: 'Admin',
          isAdmin: true,
          permissions: {},
        ),
        onPressed: () => ran = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Renew'));
    await tester.pump();

    expect(ran, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });
}
