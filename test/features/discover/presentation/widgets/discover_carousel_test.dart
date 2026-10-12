import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';

const _failure = ClassifiedFailure(ServiceFailureReason.unreachable);

/// What the shelf is asked for: moving it asks again of a changed source, as
/// a lens or a connection that moved does.
class _Source extends Notifier<int> {
  @override
  int build() => 0;

  void move() => state++;
}

final _source = NotifierProvider<_Source, int>(_Source.new);

/// What Seerr does at each ask, in turn.
List<Future<List<MediaPreview>> Function()> _asks = [];
var _asked = 0;

final _shelf = FutureProvider<List<MediaPreview>>((ref) {
  ref.watch(_source);
  return _asks[_asked++]();
}, retry: noProviderRetry);

List<MediaPreview> _titles() => const [
  MediaPreview(id: 1, title: 'Dune', mediaType: 'movie'),
  MediaPreview(id: 2, title: 'Severance', mediaType: 'tv'),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Future<List<MediaPreview>> Function()> asks,
  VoidCallback? onRetry,
}) async {
  _asks = asks;
  _asked = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audienceProvider.overrideWithValue(Audience.operator),
        seerrNumberingProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, _) => DiscoverCarousel(
                title: 'Trending this week',
                sectionId: 'test',
                items: ref.watch(_shelf),
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

/// A row of posters, or the failure, as the person sees it.
void main() {
  testWidgets('a row with nothing yet is a skeleton under its heading', (
    tester,
  ) async {
    await _pump(tester, asks: [() => Completer<List<MediaPreview>>().future]);
    expect(find.text('Trending this week'), findsOne);
    expect(find.byType(ShimmerPlaceholder), findsWidgets);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('asked again of a source that changed, it keeps its posters '
      'and does not drop back to a skeleton', (tester) async {
    final container = await _pump(
      tester,
      asks: [
        () async => _titles(),
        () => Completer<List<MediaPreview>>().future,
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Dune'), findsOne);

    container.read(_source.notifier).move();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_asked, 2, reason: 'asked again, with no answer yet');
    expect(container.read(_shelf).isReloading, isTrue);
    expect(find.text('Dune'), findsOne);
    expect(find.text('Severance'), findsOne);
    expect(find.byType(ShimmerPlaceholder), findsNothing);
  });

  testWidgets('a read that fails over posters it has leaves them, with no '
      'line of its own', (tester) async {
    final container = await _pump(
      tester,
      asks: [() async => _titles(), () async => throw _failure],
      onRetry: () {},
    );
    await tester.pumpAndSettle();

    container.read(_source.notifier).move();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(_shelf).hasError, isTrue);
    expect(container.read(_shelf).hasValue, isTrue);
    expect(find.text('Dune'), findsOne);
    expect(find.textContaining('row is missing'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a read that fails with nothing known says so, with Retry', (
    tester,
  ) async {
    await _pump(tester, asks: [() async => throw _failure], onRetry: () {});
    await tester.pumpAndSettle();

    expect(find.text('Trending this week'), findsOne);
    expect(
      find.text('Seerr did not answer, so this row is missing.'),
      findsOne,
    );
    expect(find.text('Retry'), findsOne);
  });

  testWidgets('an empty answer is no row at all', (tester) async {
    await _pump(tester, asks: [() async => const <MediaPreview>[]]);
    await tester.pumpAndSettle();
    expect(find.text('Trending this week'), findsNothing);
  });
}
