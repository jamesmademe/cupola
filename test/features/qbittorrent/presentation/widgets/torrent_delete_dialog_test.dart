import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_delete_dialog.dart';

/// Opens the dialog; [onResult] receives what it returned.
Future<void> _open(
  WidgetTester tester, {
  bool multi = false,
  ValueChanged<TorrentDeleteResult>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showTorrentDeleteDialog(
              context: context,
              title: multi ? 'Delete 3 torrents?' : 'Delete torrent?',
              message: 'It leaves qBittorrent.',
              multi: multi,
            );
            onResult?.call(result);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the button names the torrent, then the files once ticked', (
    tester,
  ) async {
    await _open(tester);

    final confirm = find.byType(FilledButton);
    expect(find.widgetWithText(FilledButton, 'Delete torrent'), findsOneWidget);
    // The theme's own button: nothing here is red any more.
    expect(tester.widget<FilledButton>(confirm).style, isNull);
    // The one sentence about what cannot come back sits on the option.
    expect(
      find.text(
        'Deletes the downloaded files from disk. This cannot be undone.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'Delete torrent and files'),
      findsOneWidget,
    );
  });

  testWidgets('a selection of several says torrents', (tester) async {
    await _open(tester, multi: true);
    expect(
      find.widgetWithText(FilledButton, 'Delete torrents'),
      findsOneWidget,
    );
  });

  testWidgets('what the button said is what the result carries', (
    tester,
  ) async {
    TorrentDeleteResult? result;
    await _open(tester, onResult: (r) => result = r);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete torrent and files'));
    await tester.pumpAndSettle();

    expect(result?.confirmed, isTrue);
    expect(result?.deleteFiles, isTrue);
  });
}
