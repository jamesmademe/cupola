import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';

/// The one fill a fault gets, measured where it is drawn: the amber remedy
/// fill under its amber ink, in both rooms, at the touch floor on a phone and
/// on a desktop, whose compact density would otherwise take 8 off it.
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  for (final (room, build) in [
    ('dark', AppTheme.darkTheme),
    ('light', AppTheme.lightTheme),
  ]) {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      for (final compact in [false, true]) {
        testWidgets('$room, ${platform.name}, compact $compact: amber ink '
            'on the amber fill clears 4.5:1, 44pt high', (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final theme = build();
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(platform: platform),
              home: Material(
                child: Center(
                  child: Builder(
                    builder: (context) => FilledButton(
                      onPressed: () {},
                      style: remedyFillStyle(context, compact: compact),
                      child: const Text('Paste the key again'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final button = find.byType(FilledButton);
          final style = tester.widget<FilledButton>(button).style!;
          final fill = style.backgroundColor!.resolve({})!;
          final ink = style.foregroundColor!.resolve({})!;
          final tokens = theme.extension<CupolaRoom>()!;
          expect(fill, tokens.toneAmberFill);
          expect(ink, tokens.toneAmberInk);
          expect(contrast(ink, fill), greaterThanOrEqualTo(4.5));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        });
      }
    }
  }
}
