import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_providers.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_datasets_screen.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

import '../../test_helpers/capability_overrides.dart';
import '../../test_helpers/settings_scope.dart';

/// The floor a finger can reach: iOS's 44pt.
const double _touchFloor = 44;

const _tree = [
  TrueNasDataset(
    id: 'tank',
    name: 'tank',
    pool: 'tank',
    type: 'FILESYSTEM',
    usedBytes: 1024,
    children: [
      TrueNasDataset(
        id: 'tank/media',
        name: 'tank/media',
        pool: 'tank',
        type: 'FILESYSTEM',
        usedBytes: 512,
      ),
    ],
  ),
];

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The tree's writes are capability-gated and read the saved TrueNAS
        // connection; every probe answers "unknown", i.e. live.
        ...await settingsScopeOverrides(configured: const [ServiceKey.truenas]),
        capabilityOverride(),
        truenasDatasetTreeProvider.overrideWith((ref) async => _tree),
        // The section chrome asks for the server version; the test has no
        // server.
        truenasVersionProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: TrueNasDatasetsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The height of the tappable row that carries [label]: the ListTile of a
/// leaf, or the header ListTile an ExpansionTile builds for a branch.
double _rowHeight(WidgetTester tester, String label) {
  final tile = find
      .ancestor(of: find.text(label), matching: find.byType(ListTile))
      .first;
  return tester.getSize(tile).height;
}

void main() {
  // The tree used `dense`, `VisualDensity.compact` and a 40pt tile height,
  // which is the combination the 44pt floor exists to stop: compact silently
  // takes 8 off whatever was declared.
  testWidgets('every dataset row a finger can reach is at least 44pt tall', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      _rowHeight(tester, 'tank'),
      greaterThanOrEqualTo(_touchFloor),
      reason: 'the branch row',
    );
    expect(
      _rowHeight(tester, 'media'),
      greaterThanOrEqualTo(_touchFloor),
      reason: 'the leaf row',
    );
    for (final button in tester.widgetList<IconButton>(
      find.widgetWithIcon(IconButton, Icons.info_outline_rounded),
    )) {
      expect(button.constraints?.minHeight, _touchFloor);
      expect(button.constraints?.minWidth, _touchFloor);
    }
  }, variant: TargetPlatformVariant.mobile());

  // The floor is declared, not incidental: each row carries it as its own
  // minimum instead of reaching it only because the Details button inside
  // happens to be taller.
  testWidgets('the rows declare the touch floor themselves', (tester) async {
    await _pump(tester);

    final branch = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(branch.minTileHeight, _touchFloor);
    expect(branch.visualDensity, isNot(VisualDensity.compact));

    final leaf = tester.widget<ListTile>(
      find
          .ancestor(of: find.text('media'), matching: find.byType(ListTile))
          .first,
    );
    expect(leaf.minTileHeight, _touchFloor);
    expect(leaf.visualDensity, isNot(VisualDensity.compact));
  }, variant: TargetPlatformVariant.mobile());

  // A desktop build is pointer-driven and keeps the denser tree, even in a
  // window narrow enough to paint the phone layout: the pointer is a property
  // of the build, not of the width.
  testWidgets('a desktop build keeps the pointer-only 40', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);

    final branch = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(branch.minTileHeight, 40);
  }, variant: TargetPlatformVariant.desktop());
}
