import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_only_at_home.dart';

/// Away from home, a module whose sources are reached only there says so in
/// a grey line: no band, no Retry (Q1; P-t2-5-note, 13/10).
void main() {
  Future<void> pump(WidgetTester tester, Widget frame) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(body: SingleChildScrollView(child: frame)),
    ),
  );

  final lidarr = SourceCoverage.failure(
    ServiceKey.lidarr,
    const ServiceOnlyAtHome(ServiceKey.lidarr),
  );

  testWidgets('says where the service works, and offers no Retry', (
    tester,
  ) async {
    await pump(
      tester,
      HomeModuleFrame.silent(
        title: 'Arrived',
        coverage: lidarr,
        onRetry: () {},
      ),
    );

    expect(find.text('Lidarr only works at home.'), findsOneWidget);
    expect(find.byType(FaultBand), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('over the last drawing, it says what time the rows are from', (
    tester,
  ) async {
    await pump(
      tester,
      LastKnownWords(
        words: 'As of 20:41',
        child: HomeModuleFrame.silent(
          title: 'Arrived',
          coverage: lidarr,
          onRetry: () {},
          child: const Text('Sintel'),
        ),
      ),
    );

    expect(find.text('Sintel'), findsOneWidget);
    expect(
      find.text('Lidarr only works at home. As of 20:41.'),
      findsOneWidget,
    );
  });

  testWidgets('a source that did not answer beside it still takes the band', (
    tester,
  ) async {
    await pump(
      tester,
      HomeModuleFrame.silent(
        title: 'Coming up',
        coverage: SourceCoverage.merge([
          lidarr,
          SourceCoverage.failure(
            ServiceKey.radarr,
            const SocketException('no route to host'),
          ),
        ]),
        onRetry: () {},
      ),
    );

    expect(find.byType(FaultBand), findsOneWidget);
  });
}
