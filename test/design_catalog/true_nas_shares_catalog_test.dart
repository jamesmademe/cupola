@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/presentation/shares/truenas_shares_screen.dart';

import 'catalog.dart';
import 'truenas_world.dart';

void main() {
  catalogCard(
    'TrueNasShares',
    width: 480,
    overrides: trueNasCatalogOverrides,
    scenes: [
      CatalogScene(
        'Shares · SMB on a phone: the SMB service running, the share rows, '
        "and the New FAB lifted over the shell's floating bar",
        (_) => trueNasPhone(trueNasShell(const TrueNasSharesScreen())),
        width: 390,
        height: 844,
      ),
      CatalogScene(
        'Text at 200% · Shares · SMB: the page at twice the reading size; '
        "the bar's own labels clamp at 1.3× and the FAB keeps its clearance",
        (_) => trueNasPhone(trueNasShell(const TrueNasSharesScreen())),
        width: 390,
        height: 844,
        textScale: catalogTextScale,
      ),
    ],
  );
}
