import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

/// The Renew control as the Certificates tab builds it, answered by the real
/// NPM probe through `npmAccountProvider`.
Future<void> _pump(
  WidgetTester tester, {
  required NpmAccount? account,
  required VoidCallback onPressed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...await settingsScopeOverrides(
          configured: const [ServiceKey.nginxProxyManager],
        ),
        npmAccountProvider.overrideWith((ref) async => account),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => CapabilityGatedAction.builder(
              service: ServiceKey.nginxProxyManager,
              connectionId: capabilityConnectionId(
                ref,
                ServiceKey.nginxProxyManager,
              ),
              resource: NpmResource.certificates.key,
              hint: npmCapabilityHint,
              blockedMessage: npmBlockedMessage(NpmResource.certificates),
              onTap: onPressed,
              builder: (context, gated, annotate) => TextButton(
                onPressed: gated,
                child: annotate(const Text('Renew')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a write this account cannot make stays reachable and answers', (
    tester,
  ) async {
    var ran = false;
    await _pump(
      tester,
      account: const NpmAccount(
        id: 1,
        name: 'Reader',
        isAdmin: false,
        permissions: {'certificates': 'view'},
      ),
      onPressed: () => ran = true,
    );

    // Still on screen, still named: hiding the control would hide the fact.
    final button = find.widgetWithText(TextButton, 'Renew');
    expect(button, findsOneWidget);
    // Still tappable: `onPressed: null` would take it off the screen reader's
    // path as well as off the pointer's, which is the whole point of the rule.
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);

    // The node a screen reader lands on, the one carrying the tap, has to be
    // the node carrying the hint. A `Semantics(hint:)` wrapped *around* the
    // button lands on a second, non-actionable parent node, and the reader
    // never speaks the reason.
    final spoken = tester.getSemantics(find.byType(TextButton));
    expect(spoken.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(spoken.label, 'Renew');
    expect(
      spoken.hint.contains('admin'),
      isTrue,
      reason: 'the reason has to be spoken, not only greyed',
    );

    await tester.tap(button);
    await tester.pump();

    // It answers instead of acting, and the answer's one action is the fix.
    expect(ran, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.widgetWithText(SnackBarAction, 'Change account'),
      findsOneWidget,
    );
  });

  testWidgets('an admin gets the plain control with no hint', (tester) async {
    var ran = false;
    await _pump(
      tester,
      account: const NpmAccount(
        id: 1,
        name: 'Admin',
        isAdmin: true,
        permissions: {},
      ),
      onPressed: () => ran = true,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Renew'));
    await tester.pump();

    expect(ran, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    // And the same node is unhinted when there is nothing to explain.
    expect(tester.getSemantics(find.byType(TextButton)).hint, isEmpty);
  });
}
