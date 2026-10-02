import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/add_torrent_button.dart';

void main() {
  Color inkOf(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).first,
    );
    return paragraph.text.style!.color!;
  }

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme()),
    ('dark', AppTheme.darkTheme()),
  ]) {
    // The label's `labelLarge` style carried the theme's text colour and
    // overrode the button's foreground: near-black on qBittorrent blue in
    // light theme, beside a white + glyph.
    testWidgets('the submit label and glyph share one legible ink ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: theme,
            home: const Scaffold(body: Center(child: AddTorrentButton())),
          ),
        ),
      );
      await tester.tap(find.byType(AddTorrentButton));
      await tester.pumpAndSettle();

      final submit = find.byType(FilledButton);
      expect(submit, findsOneWidget);
      final label = inkOf(
        tester,
        find.descendant(of: submit, matching: find.text('Add torrent')),
      );
      final glyph = inkOf(
        tester,
        find.descendant(of: submit, matching: find.byIcon(Icons.add_rounded)),
      );

      // The ink button: the theme's primary under its on-ink, never the
      // client's colour (the brand book: the primary is ink).
      expect(label, glyph);
      expect(label, theme.colorScheme.onPrimary);
      expect(
        contrast(label, theme.colorScheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  group('the add sheet lets go of what it made', () {
    // Three field controllers and the picked-files notifier were created each
    // time the sheet opened and never disposed.
    ({List<Object> created, List<Object> disposed}) track() {
      final created = <Object>[];
      final disposed = <Object>[];
      void record(ObjectEvent event) {
        final object = event.object;
        if (object is! TextEditingController &&
            object is! ValueNotifier<List<PlatformFile>>) {
          return;
        }
        if (event is ObjectCreated) created.add(object);
        if (event is ObjectDisposed) disposed.add(object);
      }

      FlutterMemoryAllocations.instance.addListener(record);
      addTearDown(
        () => FlutterMemoryAllocations.instance.removeListener(record),
      );
      return (created: created, disposed: disposed);
    }

    Future<_AddingQbittorrent> open(WidgetTester tester) async {
      final service = _AddingQbittorrent();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [qbittorrentServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: Center(child: AddTorrentButton())),
          ),
        ),
      );
      await tester.tap(find.byType(AddTorrentButton));
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('when it is closed without adding', (tester) async {
      final made = track();
      await open(tester);
      expect(made.created, hasLength(4));

      Navigator.of(tester.element(find.byType(Form))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(Form), findsNothing);
      expect(made.disposed, unorderedEquals(made.created));
    });

    testWidgets('when it adds, and the page still says so', (tester) async {
      final made = track();
      final service = await open(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Magnet / URL'),
        'magnet:?xt=urn:btih:abc',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add torrent'));
      await tester.pumpAndSettle();

      expect(service.added, ['magnet:?xt=urn:btih:abc']);
      expect(find.byType(Form), findsNothing);
      expect(find.text('Torrent added successfully'), findsOneWidget);
      expect(made.disposed, unorderedEquals(made.created));
    });
  });
}

/// Records the links an add handed qBittorrent.
class _AddingQbittorrent implements QbittorrentService {
  final added = <String>[];

  @override
  Future<void> addTorrentUrl(
    String url, {
    String? category,
    String? savePath,
  }) async {
    added.add(url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
