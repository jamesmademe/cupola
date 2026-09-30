import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';

import '../../test_helpers/reel_finders.dart';

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<List<ServiceKpi>> kpis,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ServiceKpiPeek(kpis: kpis, accent: const Color(0xFF4F8DF7)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('a rail whose figures could not be read', () {
    testWidgets('reads an em dash rather than vanishing', (tester) async {
      // `SizedBox.shrink()` on error makes "no figures" and "no rail"
      // the same pixels: the strip is simply gone, and a reader has no way
      // to tell a service with nothing to report from a service that could
      // not be asked. `ServiceKpi.unavailable` is the answer.
      await _pump(
        tester,
        AsyncValue.error(
          const SocketException('Connection refused'),
          StackTrace.empty,
        ),
      );

      expect(findLine(ServiceKpi.unavailableValue), findsOneWidget);
    });

    testWidgets('says why, in the card the figure would have filled', (
      tester,
    ) async {
      await _pump(
        tester,
        AsyncValue.error(
          const SocketException('Connection refused'),
          StackTrace.empty,
        ),
      );

      expect(findLineContaining('Did not answer'), findsOneWidget);
    });

    testWidgets('a refusal says it was refused, never that nothing answered', (
      tester,
    ) async {
      // P6's Plex: the header says Answering, and the rail used to say "not
      // answering" beside it about the same server.
      await _pump(
        tester,
        AsyncValue.error(
          DioException(
            requestOptions: RequestOptions(path: '/status/sessions'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/status/sessions'),
              statusCode: 401,
            ),
          ),
          StackTrace.empty,
        ),
      );

      expect(findLineContaining('Refused the key'), findsOneWidget);
      expect(findLineContaining('answer'), findsNothing);
    });

    testWidgets('announces the absence as a word, not as a dash', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AsyncValue.error(
          const SocketException('Connection refused'),
          StackTrace.empty,
        ),
      );

      expect(find.bySemanticsLabel(RegExp('unavailable')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a service that is not configured keeps its own placeholder', (
      tester,
    ) async {
      // The one error the rail must stay out of: an unconfigured service is
      // already answered by `NotConfiguredPlaceholder` on the page below, and
      // a rail of em dashes over it would read as a fault the user has to fix
      // rather than a service they never set up.
      await _pump(
        tester,
        AsyncValue.error(Exception('Sonarr not configured'), StackTrace.empty),
      );

      expect(find.byType(ListView), findsNothing);
      expect(findLine(ServiceKpi.unavailableValue), findsNothing);
    });
  });

  group('the rail it already drew', () {
    testWidgets('still draws its figures', (tester) async {
      await _pump(
        tester,
        const AsyncValue.data([
          ServiceKpi(label: 'Series', value: '128', icon: Icons.tv_rounded),
        ]),
      );

      expect(findLine('128'), findsOneWidget);
    });

    testWidgets('still collapses when a service reports no figures at all', (
      tester,
    ) async {
      await _pump(tester, const AsyncValue.data(<ServiceKpi>[]));

      expect(find.byType(ListView), findsNothing);
    });
  });
}
