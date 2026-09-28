import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
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

      expect(label, glyph);
      expect(label, ServiceTheme.foregroundOn(AppColors.qbittorrent));
      expect(contrast(label, AppColors.qbittorrent), greaterThanOrEqualTo(4.5));
    });
  }
}
