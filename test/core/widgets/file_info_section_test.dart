import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/file_info_section.dart';
import 'package:cupola/core/widgets/machine_name.dart';

void main() {
  group('FileInfoSection', () {
    testWidgets('renders nothing without a path', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FileInfoSection())),
      );

      // Should render SizedBox.shrink()
      expect(find.byType(FileInfoSection), findsOneWidget);
      expect(find.text('Library path'), findsNothing);
    });

    testWidgets('renders path when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FileInfoSection(path: '/movies/Avatar')),
        ),
      );

      expect(find.text('File'), findsNothing);
      expect(find.text('Library path'), findsOneWidget);
      expect(find.text('/movies/Avatar'), findsOneWidget);
      expect(find.byIcon(Icons.storage_rounded), findsOneWidget);
    });

    testWidgets('.file names the file in full, then the folder', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileInfoSection.file(
              fileName: 'Avatar (2009) Bluray-1080p.mkv',
              path: '/movies/Avatar (2009)',
            ),
          ),
        ),
      );

      expect(find.text('File'), findsNothing);
      final name = tester.widget<MachineName>(find.byType(MachineName));
      expect(name.name, 'Avatar (2009) Bluray-1080p.mkv');
      expect(find.byTooltip('Copy file name'), findsOneWidget);
      expect(find.byTooltip('Copy release name'), findsNothing);
      expect(find.text('/movies/Avatar (2009)'), findsOneWidget);
      expect(find.byIcon(Icons.storage_rounded), findsOneWidget);
      // The file and the folder, each read whole after its label.
      expect(
        find.semantics.byValue('Avatar (2009) Bluray-1080p.mkv'),
        findsOne,
      );
      expect(find.semantics.byValue('/movies/Avatar (2009)'), findsOne);
      expect(find.semantics.byLabel('Library path'), findsOne);
    });

    testWidgets('.file leads with the file in the ink; the release and the '
        'folder are secondary, and the folder is mono', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: FileInfoSection.file(
              fileName: 'Avatar (2009) Bluray-1080p.mkv',
              releasedAs: 'Avatar.2009.1080p.BluRay.x264-GROUP',
              path: '/movies/Avatar (2009)',
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(FileInfoSection));
      final ink = Theme.of(context).colorScheme.onSurface;
      final dim = CupolaThemeColors.of(context).dimText;

      final names = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      // The page title says what; this card says which copy, so the file is
      // its lead. It used to be dim, under a brighter, heavier folder.
      expect(names.first.style!.color, ink);
      expect(names.first.style!.fontFamily, AppTheme.monoFontFamily);
      expect(names.last.style!.color, dim);

      final folder = tester.widget<Text>(find.text('/movies/Avatar (2009)'));
      expect(folder.style!.fontFamily, AppTheme.monoFontFamily);
      expect(folder.style!.color, dim);
      expect(folder.maxLines, isNull);
    });

    testWidgets('the folder alone keeps its title in the text face and draws '
        'the path in mono, dim', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: FileInfoSection(path: '/tv/Breaking Bad')),
        ),
      );
      final context = tester.element(find.byType(FileInfoSection));

      final title = tester.widget<Text>(find.text('Library path'));
      expect(title.style!.fontFamily, isNot(AppTheme.monoFontFamily));
      final path = tester.widget<Text>(find.text('/tv/Breaking Bad'));
      expect(path.style!.fontFamily, AppTheme.monoFontFamily);
      expect(path.style!.color, CupolaThemeColors.of(context).dimText);
      expect(
        find.semantics.byLabel('Library path, /tv/Breaking Bad'),
        findsOne,
      );
    });

    testWidgets('.file says what a renamed file was released as', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileInfoSection.file(
              fileName: 'Avatar (2009) Bluray-1080p.mkv',
              releasedAs: 'Avatar.2009.1080p.BluRay.x264-GROUP',
              path: '/movies/Avatar (2009)',
            ),
          ),
        ),
      );

      final names = tester
          .widgetList<MachineName>(find.byType(MachineName))
          .toList();
      expect(names.map((name) => name.name), [
        'Avatar (2009) Bluray-1080p.mkv',
        'Avatar.2009.1080p.BluRay.x264-GROUP',
      ]);
      expect(names.last.caption, 'Released as');
      expect(find.byTooltip('Copy release name'), findsOneWidget);
    });

    testWidgets('tints the storage glyph with the page accent', (tester) async {
      const radarrAmber = Color(0xFFF59E0B);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileInfoSection(path: '/movies', accent: radarrAmber),
          ),
        ),
      );

      // One accent per screen: the glyph used to be `colorScheme.primary`
      // indigo, which is a second accent on an amber or violet page. The
      // accent is walked against the well it sits in, so it is the page's hue
      // at a lightness that reads rather than the raw brand byte.
      final context = tester.element(find.byType(FileInfoSection));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.storage_rounded)).color,
        ServiceTheme.onTint(
          radarrAmber,
          surface: Theme.of(context).colorScheme.surfaceContainerHighest,
          tintAlpha: 0,
        ),
      );
    });

    testWidgets('a long path wraps whole, without overflowing', (tester) async {
      const longPath =
          '/very/long/path/to/movies/that/should/wrap/rather/than/be/cut';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 200, child: FileInfoSection(path: longPath)),
          ),
        ),
      );

      expect(find.text('File'), findsNothing);
      expect(find.text('Library path'), findsOneWidget);
      expect(find.text(longPath), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
