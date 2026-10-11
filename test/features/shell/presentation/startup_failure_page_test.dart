/// The page a start that stopped draws instead of a black window: the cause
/// once, Retry as the remedy, and the platform's words behind Why?.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/domain/startup_failure.dart';
import 'package:cupola/features/shell/presentation/startup_failure_page.dart';

final _failure = StartupFailure(
  step: StartupStep.connections,
  error: PlatformException(
    code: '-25308',
    message: 'User interaction is not allowed.',
  ),
  platform: TargetPlatform.iOS,
);

void main() {
  testWidgets('says the cause once and offers Retry in the fault fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupFailureApp(failure: _failure, onRetry: () async {}),
    );

    expect(
      find.text("Cupola could not read your saved connections"),
      findsOneWidget,
    );
    expect(find.text("The Keychain didn't hand them over."), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Retry'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
      findsOneWidget,
    );
    // The platform's words are behind Why?, not on the page.
    expect(find.textContaining('User interaction'), findsNothing);
    await tester.tap(find.text('Why?'));
    await tester.pump();
    expect(
      find.text('User interaction is not allowed. (-25308)'),
      findsOneWidget,
    );
  });

  testWidgets('Retry runs the start once, and is held while it runs', (
    tester,
  ) async {
    var runs = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      StartupFailureApp(
        failure: _failure,
        onRetry: () {
          runs++;
          return pending.future;
        },
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(runs, 1);

    pending.complete();
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(runs, 2);
  });

  testWidgets('the headline is what a screen reader lands on first', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      StartupFailureApp(failure: _failure, onRetry: () async {}),
    );
    expect(
      tester.getSemantics(
        find.text("Cupola could not read your saved connections"),
      ),
      matchesSemantics(
        label: "Cupola could not read your saved connections",
        isHeader: true,
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('a desktop window keeps a strip to move it by', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      StartupFailureApp(failure: _failure, onRetry: () async {}),
    );

    final closes = find.byTooltip('Close').evaluate().length;
    final exception = tester.takeException();
    // Reset inside the body: the binding checks it before any tear-down runs.
    debugDefaultTargetPlatformOverride = null;
    expect(exception, isNull);
    expect(closes, 1);
  });

  testWidgets('Forget saved keys asks first, then forgets once', (
    tester,
  ) async {
    var forgets = 0;
    await tester.pumpWidget(
      StartupFailureApp(
        failure: _failure,
        onRetry: () async {},
        onForgetKeys: () async => forgets++,
      ),
    );

    await tester.tap(find.text('Forget saved keys'));
    await tester.pumpAndSettle();
    expect(find.text('Forget the saved keys?'), findsOneWidget);
    expect(
      find.text(
        'Addresses, Home and your preferences stay. Each service asks for '
        'its key or password again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(forgets, 0);

    await tester.tap(find.text('Forget saved keys'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget keys'));
    await tester.pumpAndSettle();
    expect(forgets, 1);
  });

  testWidgets('a store that never answered offers no forgetting', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupFailureApp(
        failure: StartupFailure(
          step: StartupStep.connections,
          error: TimeoutException(null),
          platform: TargetPlatform.iOS,
        ),
        onRetry: () async {},
        onForgetKeys: () async {},
      ),
    );
    expect(find.text('Forget saved keys'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}
