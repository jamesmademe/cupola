import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A module whose source answered with a refusal leads with the fix the
/// refusal names: asking again with the same token is refused again.
void main() {
  Future<void> pump(WidgetTester tester, Widget frame) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(body: SingleChildScrollView(child: frame)),
    ),
  );

  DioException status(int code) => DioException(
    requestOptions: RequestOptions(path: '/'),
    response: Response(
      requestOptions: RequestOptions(path: '/'),
      statusCode: code,
    ),
    type: DioExceptionType.badResponse,
  );

  testWidgets('a refused token offers its fix, and no Retry', (tester) async {
    await pump(
      tester,
      HomeModuleFrame.silent(
        title: 'Continue watching',
        coverage: SourceCoverage.failure(ServiceKey.plex, status(401)),
        onRetry: () {},
      ),
    );

    expect(find.text('Paste the token again'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('beside a source that can still answer, Retry follows the fix', (
    tester,
  ) async {
    await pump(
      tester,
      HomeModuleFrame.silent(
        title: 'Continue watching',
        coverage: SourceCoverage.merge([
          SourceCoverage.failure(ServiceKey.plex, status(401)),
          SourceCoverage.failure(ServiceKey.jellyfin, status(500)),
        ]),
        onRetry: () {},
      ),
    );

    expect(find.text('Paste the token again'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a fault with no fix in a form keeps Retry as the remedy', (
    tester,
  ) async {
    await pump(
      tester,
      HomeModuleFrame.silent(
        title: 'Continue watching',
        coverage: SourceCoverage.failure(ServiceKey.plex, status(500)),
        onRetry: () {},
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
  });
}
