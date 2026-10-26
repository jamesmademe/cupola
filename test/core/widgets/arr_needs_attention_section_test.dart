import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_overview.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/settings_scope.dart';

/// Two faults held, then a queue that stops answering over them.
class _Attention
    extends AsyncNotifier<List<ArrAttentionItem<SonarrAttentionKind>>> {
  @override
  Future<List<ArrAttentionItem<SonarrAttentionKind>>> build() async => const [
    ArrAttentionItem(
      kind: SonarrAttentionKind.stalled,
      headline: 'Stuck · Slow Horses S04 E02',
      detail: 'qBittorrent',
      count: 2,
    ),
  ];

  void stopAnswering() => state = AsyncError(
    DioException(
      requestOptions: RequestOptions(path: '/api/v3/queue'),
      type: DioExceptionType.receiveTimeout,
    ),
    StackTrace.empty,
  );
}

final _attention =
    AsyncNotifierProvider<
      _Attention,
      List<ArrAttentionItem<SonarrAttentionKind>>
    >(_Attention.new);

final _queue = Provider<AsyncValue<ArrRecordPage>>(
  (ref) => const AsyncData(ArrRecordPage(records: [], total: 1)),
);

void main() {
  testWidgets('a source that failed over rows it holds keeps its count', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: await settingsScopeOverrides(
          configured: [ServiceKey.sonarr],
        ),
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArrNeedsAttentionSection<SonarrAttentionKind>(
                service: ServiceKey.sonarr,
                items: _attention,
                queueRecords: _queue,
                retry: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    ProviderScope.containerOf(
      tester.element(
        find.byType(ArrNeedsAttentionSection<SonarrAttentionKind>),
      ),
    ).read(_attention.notifier).stopAnswering();
    await tester.pumpAndSettle();

    // The rows are still drawn under the failure, so the header still counts
    // them: it reads the retained value, never a dash over rows on screen.
    expect(find.text('Stuck · Slow Horses S04 E02'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('a source that never answered reads a dash, not a zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...await settingsScopeOverrides(configured: [ServiceKey.sonarr]),
          _attention.overrideWith(_NeverAnswers.new),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArrNeedsAttentionSection<SonarrAttentionKind>(
                service: ServiceKey.sonarr,
                items: _attention,
                queueRecords: _queue,
                retry: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}

class _NeverAnswers extends _Attention {
  @override
  Future<List<ArrAttentionItem<SonarrAttentionKind>>> build() =>
      Future.error(StateError('no answer'));
}
