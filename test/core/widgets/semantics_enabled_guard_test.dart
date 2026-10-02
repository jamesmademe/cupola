import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// A control the user can reach is never published as disabled:
/// **no `Semantics(enabled: false)`.**
///
/// A cross-service control whose target is not set up here (Open in Radarr
/// with no Radarr) is dimmed but tappable, keeps its 44pt target and names the
/// service in its hint, so that a tap says why and opens the setup. Published
/// as `enabled: false`, a screen reader drops it from the focus order, or
/// reads it as dead, and the one person who cannot see the dimming learns
/// nothing, while a sighted user can still tap it. `CrossServiceAction` and
/// `GatedAffordance` are the shape that does this right; `PressableScale`
/// carries the hint through a control that cannot act.
///
/// A source scan, because the regression is a single named argument in a diff
/// that otherwise reads as accessibility care. It reads every `Semantics(…)`
/// and `SemanticsProperties(…)` call in `lib/` through `code_scan.dart` and
/// fails on an `enabled:` that is the literal `false`. A widget that merely
/// takes an `enabled: false` of its own (`ListTile`, `GatedAffordance`) is not
/// a `Semantics` call and is not read.
///
/// What it cannot see: an `enabled:` handed a variable
/// (`enabled: onDecrement != null`, a stepper at its bound, which truly cannot
/// act) is a judgement made where it is written, not a literal this can read,
/// and a Material button with a null `onPressed` publishes the same state by
/// itself.
void main() {
  final files = libCode();
  final opener = RegExp(r'\b(?:Semantics|SemanticsProperties)\(');

  List<CodeCall> callsIn(String path, String code) =>
      callsOf(path, code, opener);

  test('lib/ has Semantics calls to scan', () {
    final calls = [for (final file in files) ...callsIn(file.path, file.code)];
    // A scanner that found nothing would pass the check below.
    expect(calls.length, greaterThan(100));
    expect(calls.where((call) => call.names('enabled')), isNotEmpty);
  });

  test('no Semantics is published as disabled', () {
    final offenders = [
      for (final file in files)
        for (final call in callsIn(file.path, file.code))
          if (call.named['enabled'] == 'false') call.where,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A cross-service control that is not set up is dimmed but tappable, '
          'keeps its 44pt target, and names the service in its hint: '
          'CrossServiceAction / GatedAffordance, or PressableScale with a '
          'semanticHint. Never Semantics(enabled: false).',
    );
  });

  group('the matcher', () {
    test('catches a literal false in either spelling, and passes the rest', () {
      const planted = '''
Semantics(button: true, enabled: false, child: x);
Semantics.fromProperties(
  properties: SemanticsProperties(enabled: false, label: 'a'),
  child: x,
);
Semantics(enabled: true, child: x);
Semantics(enabled: onTap != null, child: x);
ListTile(enabled: false, title: t);
GatedAffordance.builder(enabled: false, hint: 'h');
// Semantics(enabled: false) in a comment.
final s = 'Semantics(enabled: false)';
Semantics(label: 'enabled: false', child: x);
MergeSemantics(enabled: false, child: x);
''';
      final caught = [
        for (final call in callsIn('lib/zz_planted.dart', codeOf(planted)))
          if (call.named['enabled'] == 'false') call.where,
      ];
      expect(caught, ['lib/zz_planted.dart:1', 'lib/zz_planted.dart:3']);
    });
  });
}
