import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Weight Ceiling Rule from DESIGN.md: **800 is Display's and nothing
/// else's; Headline and the app-bar title stop at 700; every other role, and
/// every `.weight()` override on it, stops at 600.** The one exception is the
/// KPI figure, at 700, because it is the answer its card exists for.
///
/// It is a source scan because the failure is invisible in review. Until
/// 2026-09-22 roughly 300 call sites asked for 700–800 while bare `TextStyle`s
/// rendered Regular whatever they asked for; once the weights reached Inter's
/// `wght` axis the desktop shell read as bold everywhere. A selected tab at 700
/// looks like a reasonable local choice in a diff, and only reads as noise once
/// twenty of them are on one screen.
///
/// A new heavy weight either belongs to one of the roles above — in which case
/// take the role, which already carries its weight — or it goes in [allowed]
/// below with the reason, in the diff.
void main() {
  /// Heavy weights that are allowed, keyed by file and then by how the source
  /// line carrying the weight begins, once trimmed. Keyed by content rather than
  /// line number so an unrelated edit above a site does not break the scan;
  /// each entry must match exactly one heavy-weight line, so an entry whose
  /// site has gone fails too instead of quietly allowing the next one.
  const allowed = <String, List<String>>{
    // The app-bar title: `titleLarge` lifted to the 700 ceiling.
    'lib/core/theme.dart': ['.weight(FontWeight.w700)'],
    // The ramp itself: Display at 800 (Small at 700) and Headline at 700.
    // The ramp reads its weights from the constants generated from
    // `design/tokens/core.json`, so a heavier role added there fails here.
    'lib/core/generated/design_tokens.g.dart': [
      'static const FontWeight typeDisplayLargeFontWeight = FontWeight.w800;',
      'static const FontWeight typeDisplayMediumFontWeight = FontWeight.w800;',
      'static const FontWeight typeDisplaySmallFontWeight = FontWeight.w700;',
      'static const FontWeight typeHeadlineLargeFontWeight = FontWeight.w700;',
      'static const FontWeight typeHeadlineMediumFontWeight = FontWeight.w700;',
      'static const FontWeight typeHeadlineSmallFontWeight = FontWeight.w700;',
    ],
    // The KPI figure, the rule's one named exception.
    'lib/core/widgets/service_kpi_peek.dart': ['.weight(FontWeight.w700)'],
    // The onboarding close headline: a Display role (`displaySmall`) taken
    // to 800, the same weight as the door's punchline it answers.
    'lib/features/onboarding/presentation/widgets/onboarding_parts.dart': [
      '.weight(FontWeight.w800)',
    ],
  };

  final heavy = RegExp(r'FontWeight\.(w700|w800|w900|bold)\b');

  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  /// Code lines only: a doc comment explaining the rule may name a weight.
  Iterable<(int, String)> codeLines(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('//')) continue;
      yield (i + 1, lines[i]);
    }
  }

  test('lib/ has files to scan', () {
    expect(libFiles, isNotEmpty);
  });

  test('no role is heavier than its ceiling', () {
    final offenders = <String>[];
    final uses = <String, int>{};

    for (final file in libFiles) {
      final path = file.path;
      final fragments = allowed[path] ?? const <String>[];
      for (final (number, line) in codeLines(file)) {
        if (!heavy.hasMatch(line)) continue;
        final trimmed = line.trim();
        final hit = fragments.where(trimmed.startsWith).toList();
        if (hit.length == 1) {
          final key = '$path :: ${hit.single}';
          uses[key] = (uses[key] ?? 0) + 1;
        } else {
          offenders.add('$path:$number  ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These ask for 700 or more outside the roles that may carry it. A '
          'selected state, an active tab or an emphasised label stops at 600; '
          'a heading takes its headline role, which already carries 700. If '
          'this really is a Display, Headline, app-bar or KPI role, add it to '
          '`allowed` in this test with the reason.',
    );

    final stale = <String>[];
    allowed.forEach((path, fragments) {
      for (final fragment in fragments) {
        final count = uses['$path :: $fragment'] ?? 0;
        if (count != 1) stale.add('$path :: $fragment (matched $count)');
      }
    });
    expect(
      stale,
      isEmpty,
      reason:
          'Each allowed entry must match exactly one heavy-weight line. One '
          'that matches none has lost its site and should go; one that matches '
          'several needs a longer fragment.',
    );
  });

  test('weights are changed through .weight(), never fontWeight:', () {
    // `copyWith(fontWeight:)` and a bare `TextStyle(fontWeight:)` change the
    // field and leave Inter's `wght` axis where it was, so the text keeps
    // rendering at the role's weight: a request for 600 on a 500 role renders
    // 500. `CupolaTextStyle.weight()` moves both. Only theme.dart, which builds
    // the roles and the helper itself, sets the field directly.
    const builder = 'lib/core/theme.dart';
    final fieldWrite = RegExp(r'\bfontWeight\s*:');
    final offenders = <String>[];
    for (final file in libFiles) {
      if (file.path == builder) continue;
      for (final (number, line) in codeLines(file)) {
        if (fieldWrite.hasMatch(line)) {
          offenders.add('${file.path}:$number  ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use `.weight(FontWeight.wNNN)` from CupolaTextStyle so the weight '
          'reaches the variable font.',
    );
  });
}
