import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/front_room.dart';

const _teal = Color(0xFF4FB6A8);
const _rose = Color(0xFFE88A9A);

/// A room lit by [accent], with [child] inside it.
Widget _room(Color? accent, {Widget child = const SizedBox.expand()}) =>
    AmbientBackground(accent: accent, child: child);

Future<void> _pump(WidgetTester tester, FrontRoomLight board, Widget home) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: FrontRoomScope(light: board, child: home),
      ),
    );

void main() {
  group('FrontRoomLight', () {
    testWidgets('the deepest room in front gives the light; the lamp none', (
      tester,
    ) async {
      final board = FrontRoomLight();
      addTearDown(board.dispose);

      await _pump(tester, board, _room(_teal, child: _room(_rose)));
      await tester.pump();
      expect(board.light, _rose, reason: 'the room inside is the one painted');

      await _pump(tester, board, _room(null));
      await tester.pump();
      expect(board.light, isNull, reason: 'a room no title lights');
    });

    testWidgets('a room in a branch put away does not count', (tester) async {
      final board = FrontRoomLight();
      addTearDown(board.dispose);

      await _pump(
        tester,
        board,
        Stack(
          children: [
            BranchActivityScope(
              isActive: true,
              branchIndex: 0,
              child: _room(_teal),
            ),
            BranchActivityScope(
              isActive: false,
              branchIndex: 1,
              child: _room(_rose),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(board.light, _teal);
    });

    testWidgets('a page pushed over a room takes the light, and gives it '
        'back when it goes', (tester) async {
      final board = FrontRoomLight();
      addTearDown(board.dispose);
      final navigator = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          navigatorKey: navigator,
          builder: (context, child) =>
              FrontRoomScope(light: board, child: child!),
          home: _room(_teal),
        ),
      );
      await tester.pump();
      expect(board.light, _teal);

      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => _room(_rose)),
      );
      await tester.pumpAndSettle();
      expect(board.light, _rose);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(board.light, _teal);
    });

    testWidgets('with no room in front the light is kept', (tester) async {
      final board = FrontRoomLight();
      addTearDown(board.dispose);

      await _pump(tester, board, _room(_teal));
      await tester.pump();
      await _pump(tester, board, const SizedBox.expand());
      await tester.pump();
      expect(board.light, _teal);
    });
  });

  group('the bar in a lit room', () {
    Future<BoxDecoration> surface(WidgetTester tester, Color? light) async {
      final board = FrontRoomLight();
      addTearDown(board.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: FrontRoomScope(
            light: board,
            child: Scaffold(
              body: _room(light),
              bottomNavigationBar: FloatingBottomNavBar(
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                destinations: const [
                  FloatingNavDestination(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                  ),
                  FloatingNavDestination(
                    icon: Icons.bolt_outlined,
                    selectedIcon: Icons.bolt_rounded,
                    label: 'Activity',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.widget<Container>(
        find.byKey(const ValueKey('floating-nav-surface')),
      );
      return box.decoration! as BoxDecoration;
    }

    Color pill(WidgetTester tester) =>
        ((tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('floating-nav-indicator')),
                    )
                    .decoration
                as BoxDecoration)
            .color)!;

    testWidgets('the enamel carries a sheen of the light at its top and the '
        'pill a tint of it', (tester) async {
      final lit = await surface(tester, _teal);
      final room = CupolaRoom.of(tester.element(find.byType(Scaffold)));
      final colors = (lit.gradient! as LinearGradient).colors;
      final expected = Color.lerp(room.enamel, _teal, RoomSheen.sheenStrength)!;
      expect(colors.first.r, closeTo(expected.r, 0.01));
      expect(colors.first.g, closeTo(expected.g, 0.01));
      expect(colors.first.b, closeTo(expected.b, 0.01));
      expect(pill(tester), _teal.withValues(alpha: RoomSheen.pillTint));
    });

    testWidgets('the lamp casts no sheen, and the pill keeps the strong fill', (
      tester,
    ) async {
      final plain = await surface(tester, null);
      final room = CupolaRoom.of(tester.element(find.byType(Scaffold)));
      final colors = (plain.gradient! as LinearGradient).colors;
      expect(colors.first.r, closeTo(room.enamel.r, 0.01));
      expect(colors.first.g, closeTo(room.enamel.g, 0.01));
      expect(colors.first.b, closeTo(room.enamel.b, 0.01));
      expect(pill(tester), room.fillStrong);
    });
  });

  testWidgets('a board disposed before the leave frame ignores the leave', (
    tester,
  ) async {
    final board = FrontRoomLight();
    await _pump(tester, board, _room(_teal));
    await tester.pump();
    board.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
