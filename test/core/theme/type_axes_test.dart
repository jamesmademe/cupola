import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';

/// The type system reaches the variable axes it is drawn with.
///
/// Each bundled family is one variable file registered once. Flutter resolves
/// `fontWeight` against that single face and never touches an axis, and it
/// applies no optical size by itself, so a role that does not name its axes
/// renders the file's default instance: for Bricolage Grotesque that is 96pt
/// ExtraBold at full width. These tests measure the real faces.
Future<void> _load(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

double? _axis(TextStyle style, String axis) {
  for (final variation in style.fontVariations ?? const <FontVariation>[]) {
    if (variation.axis == axis) return variation.value;
  }
  return null;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _load('Bricolage Grotesque', 'assets/fonts/BricolageGrotesque.ttf');
    await _load('Onest', 'assets/fonts/Onest.ttf');
    await _load('Geist Mono', 'assets/fonts/GeistMono.ttf');
  });

  group('every slot of the text theme names its axes', () {
    final theme = AppTheme.darkTheme().textTheme;
    final slots = <String, TextStyle?>{
      'displayLarge': theme.displayLarge,
      'displayMedium': theme.displayMedium,
      'displaySmall': theme.displaySmall,
      'headlineLarge': theme.headlineLarge,
      'headlineMedium': theme.headlineMedium,
      'headlineSmall': theme.headlineSmall,
      'titleLarge': theme.titleLarge,
      'titleMedium': theme.titleMedium,
      'titleSmall': theme.titleSmall,
      'bodyLarge': theme.bodyLarge,
      'bodyMedium': theme.bodyMedium,
      'bodySmall': theme.bodySmall,
      'labelLarge': theme.labelLarge,
      'labelMedium': theme.labelMedium,
      'labelSmall': theme.labelSmall,
    };

    for (final MapEntry(key: name, value: style) in slots.entries) {
      test(name, () {
        expect(style, isNotNull);
        expect(
          _axis(style!, 'wght'),
          style.fontWeight!.value.toDouble(),
          reason: '$name sets wght to its weight',
        );
        if (style.fontFamily == AppTheme.displayFontFamily) {
          expect(_axis(style, 'wdth'), isNotNull, reason: '$name wdth');
          expect(
            _axis(style, 'opsz'),
            style.fontSize,
            reason: '$name draws at its own optical size',
          );
        } else {
          expect(style.fontFamily, AppTheme.fontFamily);
        }
      });
    }

    test('display, headline and the large title are the display face', () {
      for (final name in [
        'displayLarge',
        'displayMedium',
        'displaySmall',
        'headlineLarge',
        'headlineMedium',
        'headlineSmall',
        'titleLarge',
      ]) {
        expect(slots[name]!.fontFamily, 'Bricolage Grotesque', reason: name);
      }
    });
  });

  test('re-weighting keeps the width and the optical size', () {
    final screen = AppType.screen;
    final lighter = screen.weight(FontWeight.w500);
    expect(_axis(lighter, 'wght'), 500);
    expect(_axis(lighter, 'wdth'), DesignTokens.typeRoleScreenFontWidth);
    expect(_axis(lighter, 'opsz'), DesignTokens.typeRoleScreenFontSize);
  });

  test('the mono role sets 450 on its own axis', () {
    expect(_axis(AppType.mono, 'wght'), 450);
    final body = AppTheme.darkTheme().textTheme.bodyMedium!.mono;
    expect(body.fontFamily, 'Geist Mono');
    expect(_axis(body, 'wght'), 450);
  });

  testWidgets('Bricolage reaches wdth, wght and opsz', (tester) async {
    const text = 'Cosmos Laundromat';
    const bare = TextStyle(fontFamily: 'Bricolage Grotesque', fontSize: 36);
    final role = AppType.screen;
    // The bare style is the file's default instance: 96pt ExtraBold at 100%.
    expect(_width(text, role), lessThan(_width(text, bare)));

    TextStyle at({double wght = 600, double wdth = 100, double opsz = 36}) =>
        bare.copyWith(
          fontVariations: [
            FontVariation('wght', wght),
            FontVariation('wdth', wdth),
            FontVariation('opsz', opsz),
          ],
        );
    expect(_width(text, at(wdth: 92)), lessThan(_width(text, at())));
    expect(_width(text, at(wght: 400)), lessThan(_width(text, at())));
    expect(_width(text, at(opsz: 12)), isNot(_width(text, at(opsz: 96))));
  });

  testWidgets('Onest reaches wght and has tabular figures', (tester) async {
    final body = AppType.body;
    final bold = body.weight(FontWeight.w600);
    expect(_width('Weight', bold), greaterThan(_width('Weight', body)));

    // Proportional digits differ in width; tabular ones share one advance.
    expect(_width('1111', body), isNot(_width('0000', body)));
    final tabular = body.tabular;
    expect(_width('1111', tabular), _width('0000', tabular));
  });

  testWidgets('Geist Mono keeps one advance at every weight', (tester) async {
    final mono = AppType.mono;
    expect(_width('iiii', mono), _width('MMMM', mono));
    // A mono face does not widen with weight, which is why its columns hold
    // when a line is emphasised.
    expect(_width('0123', mono.weight(FontWeight.w600)), _width('0123', mono));
  });
}
