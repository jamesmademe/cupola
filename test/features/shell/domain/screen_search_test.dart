import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/domain/screen_search.dart';

void main() {
  group('ScreenSearchTarget', () {
    testWidgets('a screen registers its own field', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScreenSearchTarget(
            focusNode: node,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(container.read(screenSearchFocusProvider), same(node));
    });

    // The bug this guards: deregistration has to happen on the way out, and on
    // the way out `ref` is a deactivated BuildContext that Riverpod refuses to
    // serve. Every teardown of a screen with a search field took that branch,
    // so the crash was one pop away on ⌘F-capable screens.
    testWidgets('tearing the screen down clears the registry, not the app', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScreenSearchTarget(
            focusNode: node,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(screenSearchFocusProvider), isNull);
    });

    // Two screens overlap for a frame during a route transition. The outgoing
    // one must not unregister the field the incoming one just claimed —
    // otherwise ⌘F goes dead on arrival, which is worse than not being offered.
    testWidgets('an outgoing screen does not unregister the incoming field', (
      tester,
    ) async {
      final outgoing = FocusNode();
      final incoming = FocusNode();
      addTearDown(outgoing.dispose);
      addTearDown(incoming.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Future<void> pumpTargets(List<FocusNode> nodes) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Column(
            children: [
              for (final node in nodes)
                ScreenSearchTarget(
                  // Keyed so the reconciler matches by identity: removing the
                  // first child must not re-create the second's element, or the
                  // test would be measuring a rebuild instead of a transition.
                  key: ValueKey(node),
                  focusNode: node,
                  child: const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );

      await pumpTargets([outgoing]);
      await tester.pump();

      // The incoming screen mounts and claims the registry while the outgoing
      // one is still in the tree, then the outgoing one is removed.
      await pumpTargets([outgoing, incoming]);
      await tester.pump();
      expect(container.read(screenSearchFocusProvider), same(incoming));

      await pumpTargets([incoming]);
      await tester.pump();

      expect(container.read(screenSearchFocusProvider), same(incoming));
    });

    // The hazard the deferral introduces, and the reason deregistration is
    // keyed on which registration was last rather than on the node: a target
    // whose element is re-created registers the *same* node from a new State,
    // and the old State's pending clear would otherwise fire on top of it.
    testWidgets('a re-created target keeps its own registration', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Future<void> pumpAt(bool nested) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: nested
              ? Center(
                  child: ScreenSearchTarget(
                    focusNode: node,
                    child: const SizedBox.shrink(),
                  ),
                )
              : ScreenSearchTarget(
                  focusNode: node,
                  child: const SizedBox.shrink(),
                ),
        ),
      );

      await pumpAt(false);
      await tester.pump();
      await pumpAt(true);
      await tester.pump();

      expect(container.read(screenSearchFocusProvider), same(node));
    });
  });
}
