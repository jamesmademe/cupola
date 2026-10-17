import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_library_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('a Readarr that does not answer says so instead of claiming an '
      'empty library', (tester) async {
    final api = FakeApiClient()
      ..getException = DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/v1/author'),
        reason: 'Connection refused',
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [ServiceKey.readarr]),
          ),
          readarrServiceProvider.overrideWith((ref) => ReadarrService(api)),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const ReadarrLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The error branch was written and never reachable: `getAuthors` answered
    // a dead server with `[]`, which this screen drew as an empty library.
    expect(find.text('Your Readarr library is empty'), findsNothing);
    expect(find.byType(ServiceOfflineState), findsOneWidget);
    expect(find.text('Readarr did not answer'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('an empty library says where authors come from', (tester) async {
    final api = FakeApiClient()..getResponseData = const [];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [ServiceKey.readarr]),
          ),
          readarrServiceProvider.overrideWith((ref) => ReadarrService(api)),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const ReadarrLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your Readarr library is empty'), findsOneWidget);
    expect(find.text('Authors are added in Readarr itself.'), findsOneWidget);
  });
}
