import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
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

Color? _plate(WidgetTester tester) =>
    tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor;

Color _ink(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    )
    .style!
    .color!;

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
      'a failure with no cause attached is a fault plate, never red',
      (tester) async {
        // A string says nothing about a host. Red is "did not answer", and a
        // form that cannot be saved did not ask anybody anything.
        await _fire(
          tester,
          (context) => SnackBarHelper.error(context, 'Failed.', detail: 'why'),
        );

        final context = tester.element(find.byType(Scaffold));
        final scheme = Theme.of(context).colorScheme;
        expect(_plate(tester), statusToneFill(scheme, StatusTone.warning));
        expect(_plate(tester), isNot(scheme.error));
      },
    );
  });

  group('SnackBarHelper.error tone', () {
    for (final (room, theme) in [
      ('dark', AppTheme.darkTheme()),
      ('light', AppTheme.lightTheme()),
    ]) {
      testWidgets('$room: a refused key is an amber plate with legible ink', (
        tester,
      ) async {
        await _fire(
          tester,
          (context) => SnackBarHelper.error(
            context,
            "Couldn't change monitoring in Radarr.",
            detail: _status(401),
          ),
          theme: theme,
        );

        final amber = statusToneFill(theme.colorScheme, StatusTone.warning);
        expect(_plate(tester), amber);
        expect(_plate(tester), isNot(theme.colorScheme.error));
        final ink = _ink(tester);
        expect(ink, ServiceTheme.foregroundOn(amber));
        expect(_contrast(ink, amber), greaterThanOrEqualTo(4.5));
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

        final red = statusToneFill(theme.colorScheme, StatusTone.error);
        expect(_plate(tester), red);
        expect(_contrast(_ink(tester), red), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('a cause already in the words tones the plate and prints '
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

      final scheme = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;
      expect(
        _snackText(tester),
        'Could not stop playback. Jellyfin did not answer.',
      );
      expect(_plate(tester), statusToneFill(scheme, StatusTone.error));
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

      final scheme = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;
      expect(_plate(tester), statusToneFill(scheme, StatusTone.warning));
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
