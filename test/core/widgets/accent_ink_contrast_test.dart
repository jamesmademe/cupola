import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/connection_badge.dart';
import 'package:cupola/core/widgets/file_info_section.dart';
import 'package:cupola/core/widgets/release_list_widgets.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/tag_chip.dart';

/// Accent and status ink on the shared widgets clears AA against the ground it
/// is actually painted on, in both themes.
///
/// The defect this pins: each of these widgets painted its label or glyph in
/// the raw accent byte, which is a brand colour and not an ink. The bright
/// accents (Radarr's amber, SABnzbd's gold, Plex's ochre, the status green and
/// yellow) read comfortably at night and fall to about 1.5–2:1 on paper, so a
/// review done in dark theme passes all of them. Every case below is measured
/// in light *and* dark against the composite the widget sits on — the tint of
/// its own tone over the surface underneath — because that composite, not the
/// surface, is what the eye reads the ink against.
///
/// A service hands these widgets the lamp now (`ServiceKey.accent`), which the
/// walk resolves to the room's ink — that is the first case. The brand bytes
/// stay as the hardest colours a caller could pass, alongside the tones these
/// widgets do still carry: the walk has to hold for anything it is handed.
void main() {
  const worstAccents = <String, Color>{
    'a service (the lamp)': AppColors.lamp,
    'radarr': AppColors.radarr,
    'sabnzbd': AppColors.sabnzbd,
    'plex': AppColors.plex,
    'success': AppColors.success,
    'warning': AppColors.warning,
  };

  final cases = <_InkCase>[
    _InkCase(
      'TagChip',
      build: (accent) =>
          TagChip(text: 'Tag', color: accent, icon: Icons.label_outline),
      ground: (scheme, accent) => _tint(accent, 0.12, scheme.surface),
    ),
    _InkCase(
      'TagChip on a card',
      build: (accent) => Builder(
        builder: (context) => TagChip(
          text: 'Tag',
          color: accent,
          surface: Theme.of(context).colorScheme.surfaceContainer,
        ),
      ),
      ground: (scheme, accent) => _tint(accent, 0.12, scheme.surfaceContainer),
    ),
    _InkCase(
      'ConnectionBadge',
      build: (accent) => ConnectionBadge(label: 'Home', accent: accent),
      ground: (scheme, accent) => _tint(accent, 0.14, scheme.surface),
    ),
    _InkCase(
      'AppSheetHeader glyph',
      build: (accent) =>
          AppSheetHeader(title: 'Sheet', icon: Icons.tune, accent: accent),
      ground: (scheme, accent) => _tint(accent, 0.14, scheme.surfaceContainer),
      inks: () => find.byIcon(Icons.tune),
    ),
    _InkCase(
      'FileInfoSection glyph',
      build: (accent) => FileInfoSection(path: '/movies', accent: accent),
      ground: (scheme, _) => scheme.surfaceContainerHighest,
      inks: () => find.byIcon(Icons.storage_rounded),
    ),
  ];

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light
        ? AppTheme.lightTheme()
        : AppTheme.darkTheme();
    final scheme = theme.colorScheme;

    group('${brightness.name} theme', () {
      for (final c in cases) {
        for (final entry in worstAccents.entries) {
          testWidgets('${c.name} on ${entry.key}', (tester) async {
            await _pump(tester, theme, c.build(entry.value));
            _expectLegible(
              tester,
              root: c.inks?.call() ?? find.byType(Scaffold),
              ground: c.ground(scheme, entry.value),
              reason: '${c.name} / ${entry.key} / ${brightness.name}',
            );
          });
        }
      }

      // The release row's score ink is a status tone on its own wash over the
      // row's card, which is `surfaceContainerHigh`, not the scaffold.
      for (final score in const [120, -40]) {
        final tone = score > 0 ? StatusTone.success : StatusTone.neutral;

        testWidgets('ScoreBadge $score', (tester) async {
          await _pump(tester, theme, ScoreBadge(score: score));
          _expectLegible(
            tester,
            root: find.text(score > 0 ? '+$score' : '$score'),
            ground: _tint(
              statusToneFill(scheme, tone),
              score > 0 ? 0.16 : 0.10,
              scheme.surfaceContainerHigh,
            ),
            reason: 'ScoreBadge $score / ${brightness.name}',
          );
        });

        testWidgets('CustomFormatChip $score', (tester) async {
          await _pump(
            tester,
            theme,
            CustomFormatChip(name: 'HDR', score: score),
          );
          _expectLegible(
            tester,
            root: find.byType(CustomFormatChip),
            ground: _tint(
              statusToneFill(scheme, tone),
              0.12,
              scheme.surfaceContainerHigh,
            ),
            reason: 'CustomFormatChip $score / ${brightness.name}',
          );
        });
      }
    });
  }
}

class _InkCase {
  const _InkCase(
    this.name, {
    required this.build,
    required this.ground,
    this.inks,
  });

  final String name;
  final Widget Function(Color accent) build;

  /// The opaque composite the widget's ink lands on, for [accent].
  final Color Function(ColorScheme scheme, Color accent) ground;

  /// Narrows the measurement to the part of the widget that sits on [ground];
  /// null measures every ink in the tree.
  final Finder Function()? inks;
}

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every glyph and run of text under [root] measures at least 4.5:1 against
/// [ground]. `Icon` paints through a `RichText` too, so one walk covers both.
void _expectLegible(
  WidgetTester tester, {
  required Finder root,
  required Color ground,
  required String reason,
}) {
  final inks = <Color>[];
  final riches = tester.widgetList<RichText>(
    find.descendant(of: root, matching: find.byType(RichText)),
  );
  // A finder that is itself a `Text`/`Icon` matches its own `RichText` as a
  // descendant; one that is not, like a leaf `RichText`, still resolves here.
  for (final rich in riches) {
    void visit(InlineSpan span, Color? inherited) {
      final color = span.style?.color ?? inherited;
      if (span is TextSpan) {
        if ((span.text ?? '').trim().isNotEmpty && color != null) {
          inks.add(color);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, color);
        }
      }
    }

    visit(rich.text, null);
  }

  expect(inks, isNotEmpty, reason: '$reason: nothing painted');
  for (final ink in inks) {
    final painted = Color.alphaBlend(ink, ground);
    expect(
      _contrast(painted, ground),
      greaterThanOrEqualTo(4.5),
      reason: '$reason: $ink on $ground',
    );
  }
}

Color _tint(Color tone, double alpha, Color surface) =>
    Color.alphaBlend(tone.withValues(alpha: alpha), surface);

/// WCAG 2.1 relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
