import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_empty_state.dart';

/// The message a failed request produces: it quotes the address, so it wraps.
const _longMessage =
    'DioException [connection timeout]: The request connection took longer '
    'than 0:00:15.000000 and it was aborted. '
    'https://radarr.example.internal:7878/api/v3/rootfolder';

Widget _host(Widget child, {Size size = const Size(400, 700)}) => MediaQuery(
  data: MediaQueryData(size: size),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  group('AppEmptyStatePage', () {
    testWidgets('a long message scrolls rather than overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _host(
          AppEmptyStatePage(
            emptyState: AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Manual import unavailable',
              message: _longMessage,
              action: FilledButton(
                onPressed: () {},
                child: const Text('Retry'),
              ),
            ),
          ),
        ),
      );

      // The defect this widget exists for: an unscrollable column taller than
      // the viewport threw during layout and clipped the words explaining the
      // failure.
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });

    testWidgets('stays centred while it fits', (tester) async {
      await tester.pumpWidget(
        _host(
          const AppEmptyStatePage(
            emptyState: AppEmptyState(
              icon: Icons.movie_filter_outlined,
              title: 'No importable files',
            ),
          ),
        ),
      );

      final viewport = tester.getRect(find.byType(Scrollable));
      final state = tester.getRect(find.byType(AppEmptyState));

      // The state fills the viewport it was given as a minimum, which is what
      // lets its own `Center` do the centring — rather than the column sitting
      // at the top of a scroll view sized to its content.
      expect(state.height, closeTo(viewport.height, 1));
      expect(state.center.dy, closeTo(viewport.center.dy, 1));
    });
  });
}
