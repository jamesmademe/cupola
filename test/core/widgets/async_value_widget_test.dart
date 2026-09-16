import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';

/// The rule: **nothing the service already said is thrown away because it
/// stopped answering.**
///
/// This widget used to call `value.when(...)`, the one shape of the Riverpod
/// API that cannot see a retained value — so an `AsyncError` carrying the
/// previous data routed straight to a red leaf, and the readout the user opened
/// the app to look at was discarded at the widget boundary, after the state
/// layer had gone to the trouble of keeping it.
///
/// `copyWithPrevious` is exactly the state Riverpod itself produces when a
/// provider that had already answered fails on a later poll. Reaching for it
/// here is deliberate: driving a real provider to the same state means letting
/// Riverpod 3's automatic retry run, which never settles, so the test would
/// hang rather than assert. The `ignore` is the cost of naming the state
/// directly instead.
// ignore: invalid_use_of_internal_member
AsyncValue<T> _failedOver<T>(T retained, {Object? error}) {
  return AsyncValue<T>.error(
    error ?? Exception('connection refused'),
    StackTrace.empty,
    // ignore: invalid_use_of_internal_member
  ).copyWithPrevious(AsyncValue<T>.data(retained));
}

Future<void> _pump(WidgetTester tester, AsyncValue<String> value) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AsyncValueWidget<String>(
          value: value,
          serviceName: 'TrueNAS',
          onRetry: () {},
          data: (data) => Text(data),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('an error over retained data keeps the data, under a band', (
    tester,
  ) async {
    final failed = _failedOver('tank DEGRADED 78%');
    expect(failed.hasError, isTrue);
    expect(failed.hasValue, isTrue);

    await _pump(tester, failed);

    // The last thing the box said before it went dark is precisely what the
    // operator came for.
    expect(find.text('tank DEGRADED 78%'), findsOneWidget);
    expect(find.byType(FaultBand), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
  });

  testWidgets('the retained readout is not dimmed', (tester) async {
    // Rule 3 of the failure grammar: dimming means *not configured* everywhere
    // else on this canvas, and the two states need opposite answers — "go set
    // this up" against "this is what it said last".
    await _pump(tester, _failedOver('tank DEGRADED 78%'));

    expect(
      find.ancestor(
        of: find.text('tank DEGRADED 78%'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  testWidgets('a cold failure still gets the full-page leaf', (tester) async {
    // The case `AppErrorState` is actually for: nothing has answered in this
    // session, so there is no readout behind the band to keep.
    await _pump(
      tester,
      AsyncValue<String>.error(
        Exception('connection refused'),
        StackTrace.empty,
      ),
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(FaultBand), findsNothing);
  });

  testWidgets('"not configured" still wins over everything', (tester) async {
    // A service with no URL saved is not an outage and must never get the
    // outage band — the answer there is "go set this up".
    final failed = _failedOver(
      'stale',
      error: Exception('TrueNAS not configured'),
    );
    await _pump(tester, failed);

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    expect(find.byType(FaultBand), findsNothing);
  });

  testWidgets('a retained value that is empty falls back to the leaf', (
    tester,
  ) async {
    // Keeping an empty list under a band would draw a band over nothing, which
    // says less than the leaf does.
    final failed = _failedOver(<String>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncValueWidget<List<String>>(
            value: failed,
            serviceName: 'TrueNAS',
            isEmpty: (data) => data.isEmpty,
            data: (data) => Text(data.join()),
          ),
        ),
      ),
    );

    expect(find.byType(AppErrorState), findsOneWidget);
  });
}
