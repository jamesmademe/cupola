import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/features/shell/presentation/branch_transition.dart';

/// A widget that spins forever, so a test can ask whether its ticker was muted.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Drives [buildBranchTransition] the way `StatefulShellRoute` does, without a
/// router: the container only ever reads `currentIndex` and the child list.
class _Harness extends StatefulWidget {
  const _Harness({required this.children, this.disableAnimations = false});

  final List<Widget> children;
  final bool disableAnimations;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;

  /// What a nav-bar tap does, from the container's point of view.
  void switchTo(int next) => setState(() => index = next);

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQueryData(disableAnimations: widget.disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: BranchTransition(currentIndex: index, children: widget.children),
    ),
  );
}

/// A probe that reports what `BranchActivityScope.isActiveOf` answers where it
/// is mounted — which is the question every gated poller in the app asks.
class _ActivityProbe extends StatelessWidget {
  const _ActivityProbe({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    '$label:${BranchActivityScope.isActiveOf(context)}',
    textDirection: TextDirection.ltr,
  );
}

/// The nearest ancestor of type [T] above [descendant].
///
/// `skipOffstage: false` throughout: the whole point of these assertions is to
/// inspect a branch that has been put away, and the default finders would refuse
/// to see either it or the [Offstage] doing the putting away.
T _ancestorOf<T extends Widget>(WidgetTester tester, Finder descendant) =>
    tester.widget<T>(
      find
          .ancestor(
            of: descendant,
            matching: find.byType(T, skipOffstage: false),
            matchRoot: false,
          )
          .first,
    );

void main() {
  group('branch cross-fade', () {
    testWidgets('a put-away branch is both Offstage and ticker-muted', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(
          children: [
            Text('branch 0'),
            Text('branch 1'),
            Text('branch 2'),
            Text('branch 3'),
          ],
        ),
      );

      expect(find.text('branch 0'), findsOneWidget);
      // Hidden branches are still mounted — that is the point of the migration —
      // but they must not be visible to a default finder.
      expect(find.text('branch 1'), findsNothing);
      expect(find.text('branch 1', skipOffstage: false), findsOneWidget);

      final hidden = find.text('branch 1', skipOffstage: false);
      expect(_ancestorOf<Offstage>(tester, hidden).offstage, isTrue);
      // The regression guard: this container reproduces go_router's TickerMode,
      // and losing it would set every hidden animation running.
      expect(_ancestorOf<TickerMode>(tester, hidden).enabled, isFalse);

      final shown = find.text('branch 0');
      expect(_ancestorOf<Offstage>(tester, shown).offstage, isFalse);
      expect(_ancestorOf<TickerMode>(tester, shown).enabled, isTrue);
    });

    testWidgets('a repeating animation in a hidden branch does not advance', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(children: [Text('branch 0'), _Spinner()]),
      );

      final spinner = tester.state<_SpinnerState>(
        find.byType(_Spinner, skipOffstage: false),
      );
      final before = spinner.controller.value;

      await tester.pump(const Duration(milliseconds: 400));

      expect(
        spinner.controller.value,
        before,
        reason: 'TickerMode should have muted it',
      );
    });

    testWidgets('both layers are onstage for the length of the fade', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(children: [Text('branch 0'), Text('branch 1')]),
      );

      tester.state<_HarnessState>(find.byType(_Harness)).switchTo(1);
      await tester.pump();
      await tester.pump(AppAnimation.durationSm ~/ 2);

      // Mid-fade: the outgoing branch is still painted, so the incoming one does
      // not appear over a hole.
      expect(find.text('branch 0'), findsOneWidget);
      expect(find.text('branch 1'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('branch 1'), findsOneWidget);
      expect(find.text('branch 0'), findsNothing);
    });

    testWidgets('the outgoing branch stops taking taps immediately', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _Harness(
          children: [
            GestureDetector(
              onTap: () => taps++,
              child: const SizedBox.expand(child: Text('branch 0')),
            ),
            const Text('branch 1'),
          ],
        ),
      );

      tester.state<_HarnessState>(find.byType(_Harness)).switchTo(1);
      await tester.pump();
      await tester.pump(AppAnimation.durationSm ~/ 2);

      await tester.tap(find.text('branch 0'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(taps, 0);
    });

    testWidgets('the incoming branch is painted on top, in both directions', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(
          children: [
            Text('branch 0'),
            Text('branch 1'),
            Text('branch 2'),
            Text('branch 3'),
          ],
        ),
      );

      /// Where the given branch sits in paint order — last is on top.
      int depthOf(int branch) {
        final layers = find
            .byType(Offstage, skipOffstage: false)
            .evaluate()
            .toList();
        return layers.indexWhere(
          (element) => find
              .descendant(
                of: find.byWidget(element.widget, skipOffstage: false),
                matching: find.text('branch $branch', skipOffstage: false),
              )
              .evaluate()
              .isNotEmpty,
        );
      }

      // Forwards: 0 -> 3.
      tester.state<_HarnessState>(find.byType(_Harness)).switchTo(3);
      await tester.pump();
      expect(depthOf(3), 3, reason: 'the incoming branch must be last');

      // Backwards: 3 -> 0, the direction that used to fade underneath an opaque
      // layer and therefore not at all.
      tester.state<_HarnessState>(find.byType(_Harness)).switchTo(0);
      await tester.pump();
      expect(
        depthOf(0),
        3,
        reason: 'a lower-numbered tab must still come out on top',
      );
    });

    testWidgets('Reduce Motion switches branches with no intermediate frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(
          disableAnimations: true,
          children: [Text('branch 0'), Text('branch 1')],
        ),
      );

      tester.state<_HarnessState>(find.byType(_Harness)).switchTo(1);
      await tester.pump();

      expect(find.text('branch 1'), findsOneWidget);
      expect(
        find.text('branch 0'),
        findsNothing,
        reason: 'no cross-fade to sit through',
      );
    });

    group('nested inside another branch', () {
      // A service's own shell is mounted INSIDE the Dashboard branch, so two of
      // these containers are in the tree at once — and `isActiveOf` resolves to
      // the nearest scope. An inner branch that published a bare `isCurrent`
      // would tell every poller under it that it was live while the branch
      // above it was put away, and would never rebuild to discover otherwise.
      testWidgets('an inner branch is not live inside an outer one that is '
          'put away', (tester) async {
        await tester.pumpWidget(
          const _Harness(
            children: [
              Text('outer 0'),
              // The inner container's branch 0 is "current" as far as the
              // inner container knows. What it must not do is say so while
              // outer 1 is the one nobody is looking at.
              _Harness(
                children: [
                  _ActivityProbe(label: 'inner'),
                  Text('inner 1'),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('inner:false', skipOffstage: false),
          findsOneWidget,
          reason: 'the outer branch holding it is put away',
        );
      });

      testWidgets('an inner branch is live once the outer one is shown', (
        tester,
      ) async {
        await tester.pumpWidget(
          const _Harness(
            children: [
              _Harness(
                children: [
                  _ActivityProbe(label: 'inner'),
                  Text('inner 1'),
                ],
              ),
              Text('outer 1'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('inner:true'), findsOneWidget);
      });
    });
  });
}
