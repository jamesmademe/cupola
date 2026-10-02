/// The search's chips are the brand book's chip: drawn at 36 inside the
/// finger's 44, and a pill whether chosen or not (APP-27).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  testWidgets('a filter chip keeps its corner and its 44pt target', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const SearchScreen(),
      overrides: [globalSearchQueryProvider.overrideWith((ref) => 'sprite')],
      surfaceSize: const Size(430, 2400),
    );

    for (final label in ['All services', 'Radarr']) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(PressableScale),
      );
      expect(tester.getSize(target.first).height, greaterThanOrEqualTo(44));
      final pill = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      final decoration = pill.decoration! as BoxDecoration;
      // Chosen or not, the corner is the pill's.
      expect(
        decoration.borderRadius,
        AppRadius.borderRadiusPill,
        reason: label,
      );
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .height,
        greaterThanOrEqualTo(36),
      );
    }

    await harness.unmount(tester);
  });
}
