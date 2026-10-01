import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// The smallest of the failure surfaces, and it owes the same three rules as
/// the largest. It also has to be tone-correct before anything copies it: the
/// blue capability banner is deliberately this widget's shape, and could not
/// have been built from it while it still carried a fill and a border.
void main() {
  Future<void> pump(WidgetTester tester, {VoidCallback? onRetry}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineErrorRetry(
            message: 'Radarr did not answer.',
            error: const SocketException('Connection refused'),
            onRetry: onRetry ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('no fill and no border: presence is the signal', (tester) async {
    // It used to be `errorContainer` at 40% behind an `error` stroke at 50%.
    // In a stack where something is down most Tuesdays, that is alarm chrome on
    // most Tuesdays, and alarm chrome that appears constantly stops being read.
    await pump(tester);

    for (final decorated in tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(InlineErrorRetry),
        matching: find.byType(DecoratedBox),
      ),
    )) {
      final decoration = decorated.decoration;
      if (decoration is BoxDecoration) {
        expect(decoration.color, isNull);
        expect(decoration.border, isNull);
      }
    }
  });

  testWidgets('Retry is the brand, never the fault tone', (tester) async {
    await pump(tester);
    final scheme = Theme.of(
      tester.element(find.byType(InlineErrorRetry)),
    ).colorScheme;

    final button = tester.widget<TextButton>(find.byType(TextButton));
    final verb = button.style!.foregroundColor!.resolve({});
    expect(verb, scheme.primary);
    // A red Retry makes the cure look like the disease.
    expect(verb, isNot(tester.widget<Icon>(find.byType(Icon)).color));
  });

  testWidgets('one sentence for the screen reader, one reachable verb', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var retried = 0;
    await pump(tester, onRetry: () => retried++);

    expect(find.bySemanticsLabel('Radarr did not answer.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, 1);
    handle.dispose();
  });

  testWidgets('the fixed-height variant still holds its slot', (tester) async {
    // The reason the variant exists: a carousel row that swaps to a failure
    // must not make the page jump.
    Future<double> heightFor(String message) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineErrorRetry.fixedHeight(
              message: message,
              error: null,
              onRetry: () {},
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(InlineErrorRetry)).height;
    }

    // The rule is that the height does not depend on the message, not that it
    // is any particular number of points.
    final short = await heightFor('Down.');
    final long = await heightFor(
      'Radarr did not answer, so the release list below is missing '
      'everything it would have contributed to this page.',
    );
    expect(short, long);
  });

  group('the glyph follows the classification', () {
    Future<Color?> glyphFor(WidgetTester tester, Object? error) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineErrorRetry(
              message: 'Unraid did not answer, so its shares are not shown.',
              error: error,
              onRetry: () {},
            ),
          ),
        ),
      );
      return tester.widget<Icon>(find.byType(Icon)).color;
    }

    ColorScheme scheme(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(InlineErrorRetry))).colorScheme;

    testWidgets('red only when nothing answered', (tester) async {
      final color = await glyphFor(
        tester,
        const SocketException('Connection refused'),
      );
      final colorScheme = scheme(tester);
      expect(
        color,
        statusToneColor(
          colorScheme,
          StatusTone.error,
          surface: colorScheme.surface,
        ),
      );
    });

    testWidgets('amber for a failure nobody can attribute, never red', (
      tester,
    ) async {
      // The sections that used to leave `error` out stayed red for this, and
      // for a refused key: the claim "did not answer" with nothing behind it.
      for (final error in <Object?>[Exception('offline'), null]) {
        final color = await glyphFor(tester, error);
        final colorScheme = scheme(tester);
        expect(
          color,
          statusToneColor(
            colorScheme,
            StatusTone.warning,
            surface: colorScheme.surface,
          ),
        );
      }
    });
  });

  testWidgets('an ended Seerr session is blue, and its remedy is in ink', (
    tester,
  ) async {
    final theme = AppTheme.darkTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: InlineErrorRetry(
            message: 'Signed out of Seerr.',
            service: ServiceKey.seerr,
            error: DioException(
              requestOptions: RequestOptions(path: '/api/v1/request'),
              type: DioExceptionType.badResponse,
              error: const SeerrSessionEnded(),
            ),
            onRetry: () {},
          ),
        ),
      ),
    );

    final colorScheme = theme.colorScheme;
    expect(
      tester.widget<Icon>(find.byType(Icon)).color,
      statusToneColor(
        colorScheme,
        StatusTone.info,
        surface: colorScheme.surface,
      ),
    );
    final remedy = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Sign in again'),
    );
    final room = theme.extension<CupolaRoom>()!;
    expect(
      remedy.style!.backgroundColor?.resolve({}),
      isNot(room.toneAmberFill),
    );
    // No request revives a session: Retry is not offered beside it.
    expect(find.text('Retry'), findsNothing);
  });
}
