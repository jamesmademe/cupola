/// A Review whose download the arr still lists after everything in it went
/// in: Sonarr keeps a season pack queued until the episodes it expected all
/// arrive. Seen live on Sonarr 4: the Review said `Sonarr has no download
/// waiting` beside a Needs you that said it had one, and offered no way out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/import/presentation/blocked_import_review_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/blocked_import_world.dart';

void main() {
  testWidgets('every file of the download went in already: nothing left to '
      'import, why it stays, and Remove download', (tester) async {
    final container = ProviderContainer(
      overrides: blockedImportOverrides(
        spentPackService(),
        queue: spentPackQueue(),
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const BlockedImportReviewPage(
            service: ServiceKey.sonarr,
            instanceId: blockedImportConnection,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing left to import'), findsOneWidget);
    expect(find.textContaining('took what this download had'), findsOneWidget);
    expect(find.textContaining('no download waiting'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Remove download'), findsOne);

    // The neutral question Needs you asks, before anything is removed.
    await tester.tap(find.text('Remove download'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });
}
