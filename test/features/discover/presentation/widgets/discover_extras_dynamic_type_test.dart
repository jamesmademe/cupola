import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_cast_list.dart';

/// Dynamic Type coverage for the cast rail.
///
/// Every one of these pairs a fixed-size visual (an avatar, a provider logo, a
/// backdrop band) with one or two lines of label, which is the shape that clips
/// at an accessibility reading size. The assertions are deliberately not
/// goldens: a `RenderFlex`/`RenderBox` overflow is reported as an exception, so
/// `takeException()` returning null *is* the "nothing clipped" assertion, and
/// the height comparisons prove the box grew with the text and stopped at the
/// clamp instead of growing forever.
void main() {
  // No image paths anywhere in these fixtures on purpose: it keeps
  // `CachedNetworkImage` (and the network) out of the widget tree.
  const cast = <DiscoverCastMember>[
    (
      id: 1,
      name: 'Mena Massoud',
      character: 'Genie / Mariner / Merchant',
      profilePath: null,
    ),
    (
      id: 2,
      name: 'Naomi Scott',
      character: 'Princess Jasmine',
      profilePath: null,
    ),
    (id: 0, name: 'Marwan Kenzari', character: 'Jafar', profilePath: null),
  ];

  /// A phone-sized host at [textScale]. The `MediaQuery` goes *inside*
  /// `MaterialApp`, which installs one of its own from the view.
  Widget host({required double textScale, required Widget child}) {
    return MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
  }

  void usePhoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('DiscoverCastList', () {
    Future<double> pumpRail(WidgetTester tester, double scale) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        host(
          textScale: scale,
          child: const DiscoverCastList(cast: cast),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Mena Massoud'), findsOneWidget);
      expect(find.text('Genie / Mariner / Merchant'), findsOneWidget);
      return tester.getSize(find.byType(ListView)).height;
    }

    testWidgets('each person is one sentence, a button when it opens', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      usePhoneView(tester);
      await tester.pumpWidget(
        host(textScale: 1, child: const DiscoverCastList(cast: cast)),
      );

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Naomi Scott, as Princess Jasmine'),
        ),
        matchesSemantics(
          label: 'Naomi Scott, as Princess Jasmine',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      // No TMDB id, so nothing to open: still one sentence, never a button.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Marwan Kenzari, as Jafar')),
        matchesSemantics(label: 'Marwan Kenzari, as Jafar'),
      );
      handle.dispose();
    });

    testWidgets('rail grows with the reading size and never clips', (
      tester,
    ) async {
      final base = await pumpRail(tester, 1.0);
      final double2x = await pumpRail(tester, 2.0);
      final double3x = await pumpRail(tester, 3.0);

      expect(double2x, greaterThan(base));
      // Compact chrome clamps at 1.6x and ellipsises past it, so 3x must not
      // grow the rail any further than 2x already did.
      expect(double3x, double2x);
    });

    testWidgets('labels fit inside the grown rail at 2x and 3x', (
      tester,
    ) async {
      for (final scale in [2.0, 3.0]) {
        final railHeight = await pumpRail(tester, scale);
        final tileHeight = tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Mena Massoud'),
                    matching: find.byType(Column),
                  )
                  .first,
            )
            .height;
        expect(
          tileHeight,
          lessThanOrEqualTo(railHeight),
          reason: 'cast tile overflowed its rail at ${scale}x',
        );
      }
    });
  });
}
