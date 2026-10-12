import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';

/// Renders the resolved activity, and counts how often it had to rebuild.
class _Probe extends ConsumerWidget {
  const _Probe({required this.builds});

  final List<PageActivity> builds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = watchPageActivity(context, ref);
    builds.add(activity);
    return Text(
      activity.isLive ? 'live' : 'paused:${activity.reason!.name}',
      textDirection: TextDirection.ltr,
    );
  }
}

void main() {
  group('watchPageActivity', () {
    testWidgets('is live with no scopes at all', (tester) async {
      final builds = <PageActivity>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: _Probe(builds: builds)),
        ),
      );

      expect(find.text('live'), findsOneWidget);
    });

    testWidgets('an inactive branch vetoes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: BranchActivityScope(
              isActive: false,
              branchIndex: 2,
              child: _Probe(builds: []),
            ),
          ),
        ),
      );

      expect(find.text('paused:branchInactive'), findsOneWidget);
    });

    testWidgets('a route pushed on top vetoes, and popping restores', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: _Probe(builds: []),
          ),
        ),
      );
      expect(find.text('live'), findsOneWidget);

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('on top')),
      );
      await tester.pumpAndSettle();

      // The probe is offstage under the pushed page, so find it without skipping.
      expect(
        find.text('paused:coveredByRoute', skipOffstage: false),
        findsOneWidget,
      );

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.text('live'), findsOneWidget);
    });

    testWidgets('the Portal covering vetoes, and costs two rebuilds', (
      tester,
    ) async {
      final covering = ValueNotifier<bool>(false);
      addTearDown(covering.dispose);
      final builds = <PageActivity>[];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PageCoverageScope(
              covering: covering,
              child: _Probe(builds: builds),
            ),
          ),
        ),
      );
      expect(find.text('live'), findsOneWidget);
      final buildsAfterMount = builds.length;

      covering.value = true;
      await tester.pump();
      expect(find.text('paused:coveredByPortal'), findsOneWidget);

      covering.value = false;
      await tester.pump();
      expect(find.text('live'), findsOneWidget);

      // Two state changes, two rebuilds: the reason the scope carries a bool
      // rather than the Portal's own animation.
      expect(builds.length - buildsAfterMount, 2);
    });

    testWidgets('a backgrounded app vetoes', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return _Probe(builds: []);
              },
            ),
          ),
        ),
      );
      expect(find.text('live'), findsOneWidget);

      capturedRef.read(appInForegroundProvider.notifier).set(false);
      await tester.pump();

      expect(find.text('paused:appBackgrounded'), findsOneWidget);
    });

    testWidgets('reports the outermost reason when several vetoes apply', (
      tester,
    ) async {
      final covering = ValueNotifier<bool>(true);
      addTearDown(covering.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: BranchActivityScope(
              isActive: false,
              branchIndex: 1,
              child: PageCoverageScope(
                covering: covering,
                child: _Probe(builds: []),
              ),
            ),
          ),
        ),
      );

      // Branch beats Portal: the branch is further from the user's eye.
      expect(find.text('paused:branchInactive'), findsOneWidget);
    });
  });
}
