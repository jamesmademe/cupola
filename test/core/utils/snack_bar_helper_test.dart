import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// Pumps a host whose only job is to give the helper a `ScaffoldMessenger`, then
/// fires [show] and settles the snackbar in.
Future<void> _fire(
  WidgetTester tester,
  void Function(BuildContext context) show, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => show(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

/// Reads the snackbar's rendered string, so an assertion sees exactly what the
/// user does — including the newline that separates the two registers.
String _snackText(WidgetTester tester) {
  final content = tester.widget<Text>(
    find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
  );
  return content.data!;
}

/// The colour the toast repaints its plate with, or null for the theme's own.
Color? _plate(WidgetTester tester) =>
    tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor;

/// The plate the toast actually sits on: the theme's toast plate.
Color _themePlate(WidgetTester tester) {
  final theme = Theme.of(tester.element(find.byType(Scaffold)));
  return theme.snackBarTheme.backgroundColor ??
      theme.colorScheme.inverseSurface;
}

/// The failure's glyph ahead of the words.
Color _glyph(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)),
    )
    .color!;

/// The tone walked against the toast's own plate, as the helper paints it.
Color _toned(WidgetTester tester, StatusTone tone) => statusToneColor(
  Theme.of(tester.element(find.byType(Scaffold))).colorScheme,
  tone,
  surface: _themePlate(tester),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/api/v3/movie'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/v3/movie'),
    statusCode: code,
  ),
);

void main() {
  group('SnackBarHelper.error detail', () {
    testWidgets('leads with the human sentence and demotes the exception', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          "Couldn't start a search in Radarr.",
          detail: Exception('404 Not Found'),
        ),
      );

      // The sentence is the opening, not a suffix after a raw type name: the
      // first thing read aloud has to be the thing the user can act on.
      expect(
        _snackText(tester),
        "Couldn't start a search in Radarr.\n404 Not Found",
      );
    });

    testWidgets('strips the Exception prefix Dart adds itself', (tester) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          'Failed.',
          detail: Exception('connection refused'),
        ),
      );

      expect(_snackText(tester), 'Failed.\nconnection refused');
      expect(_snackText(tester), isNot(contains('Exception:')));
    });

    testWidgets(
      'omits the second line entirely when nothing legible survives',
      (tester) async {
        // A bare `Exception('')` demotes to an empty string; a blank second row
        // is worse than none, so the helper drops it.
        await _fire(
          tester,
          (context) =>
              SnackBarHelper.error(context, 'Failed.', detail: Exception('')),
        );

        expect(_snackText(tester), 'Failed.');
      },
    );

    testWidgets('a null detail is the plain single-register message', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(context, 'Failed.'),
      );

      expect(_snackText(tester), 'Failed.');
    });

    testWidgets(
      'a failure with no cause attached is a fault glyph, never red',
      (tester) async {
        // A string says nothing about a host. Red is "did not answer", and a
        // form that cannot be saved did not ask anybody anything.
        await _fire(
          tester,
          (context) => SnackBarHelper.error(context, 'Failed.', detail: 'why'),
        );

        expect(_glyph(tester), _toned(tester, StatusTone.warning));
        expect(_glyph(tester), isNot(_toned(tester, StatusTone.error)));
      },
    );
  });

  group('SnackBarHelper.error tone', () {
    for (final (room, theme) in [
      ('dark', AppTheme.darkTheme()),
      ('light', AppTheme.lightTheme()),
    ]) {
      testWidgets('$room: a refused key keeps the toast plate and carries an '
          'amber glyph', (tester) async {
        await _fire(
          tester,
          (context) => SnackBarHelper.error(
            context,
            "Couldn't change monitoring in Radarr.",
            detail: _status(401),
          ),
          theme: theme,
        );

        // No tone fill behind a fault: the Presence Rule.
        expect(_plate(tester), isNull);
        expect(_glyph(tester), _toned(tester, StatusTone.warning));
        expect(
          _contrast(_glyph(tester), _themePlate(tester)),
          greaterThanOrEqualTo(3),
        );
        expect(
          tester.widget<Icon>(find.byType(Icon)).icon,
          Icons.key_off_rounded,
        );
      });

      testWidgets('$room: red is a server that did not answer, and only that', (
        tester,
      ) async {
        await _fire(
          tester,
          (context) => SnackBarHelper.error(
            context,
            "Couldn't change monitoring in Radarr.",
            detail: DioException.connectionError(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              reason: 'Connection refused',
            ),
          ),
          theme: theme,
        );

        expect(_plate(tester), isNull);
        expect(_glyph(tester), _toned(tester, StatusTone.error));
        expect(
          _contrast(_glyph(tester), _themePlate(tester)),
          greaterThanOrEqualTo(3),
        );
      });
    }

    testWidgets('a cause already in the words tones the glyph and prints '
        'nothing twice', (tester) async {
      // The write toasts say why in the classification's own words
      // (`writeFailureReason`), so the failure rides along as the cause only.
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          'Could not stop playback. Jellyfin did not answer.',
          cause: DioException.connectionError(
            requestOptions: RequestOptions(path: '/Sessions'),
            reason: 'Connection refused',
          ),
        ),
      );

      expect(
        _snackText(tester),
        'Could not stop playback. Jellyfin did not answer.',
      );
      expect(_glyph(tester), _toned(tester, StatusTone.error));
    });

    testWidgets('the cause wins over a detail that is only words', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          'Could not archive this notification.',
          detail: 'Unraid answered but refused the key.',
          cause: _status(403),
        ),
      );

      expect(_glyph(tester), _toned(tester, StatusTone.warning));
    });
  });

  group('SnackBarHelper.error transport detail', () {
    testWidgets('a DioException demotes to words, never to its own text', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          'Could not start the app sync',
          detail: DioException(
            requestOptions: RequestOptions(path: '/api/v1/command'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v1/command'),
              statusCode: 401,
            ),
          ),
        ),
      );

      expect(
        _snackText(tester),
        'Could not start the app sync\nThe server answered and refused the '
        'saved credentials. Check them in Settings.',
      );
      expect(_snackText(tester), isNot(contains('DioException')));
    });

    testWidgets('what the service said, verbatim, when it said something', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.error(
          context,
          "Couldn't delete this movie from Radarr.",
          detail: DioException(
            requestOptions: RequestOptions(path: '/api/v3/movie/1'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v3/movie/1'),
              statusCode: 404,
              data: {'message': 'Movie not found'},
            ),
          ),
        ),
      );

      expect(
        _snackText(tester),
        "Couldn't delete this movie from Radarr.\nMovie not found",
      );
    });
  });

  group('SnackBarHelper.info detail', () {
    testWidgets('carries a demoted diagnostic the same way error does', (
      tester,
    ) async {
      await _fire(
        tester,
        (context) => SnackBarHelper.info(
          context,
          'Nothing to import.',
          detail: Exception('empty folder'),
        ),
      );

      expect(_snackText(tester), 'Nothing to import.\nempty folder');
    });
  });
}
