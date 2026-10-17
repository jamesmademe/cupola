import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// A `SectionHeader` carries the page's horizontal inset itself:
/// **never wrap it in horizontal padding.**
///
/// The header pads its own sides by `AppSpacing.lg`. A `Padding` with a
/// horizontal component around it puts the title at twice the page inset, out
/// of line with the rows under it and with every other header. Where the body
/// is already inset (a `ListView(padding: …horizontal…)`), the header is built
/// with `SectionHeader.flush` / `SectionHeader.flushAction`, which drop their
/// own side padding, so the title lines up with the rows.
///
/// A source scan, because the regression is one plausible wrapper in a diff.
/// It reads every `Padding(…)` call in `lib/` through `code_scan.dart` and
/// fails when the `child:` is a `SectionHeader(…)` (any constructor) and the
/// `padding:` has a horizontal component. A wrapper that only adds vertical
/// space is fine.
///
/// What it cannot see: a header inside a body whose padding is set elsewhere
/// (a `ListView` with side padding and the default constructor), which is
/// the other half of the rule and is held by review and the `.inset` doc.
void main() {
  final opener = RegExp(r'\bPadding\(');
  final headerChild = RegExp(r'^(?:const\s+)?SectionHeader(?:\.\w+)?\(');

  /// Where [path]'s [code] wraps a SectionHeader in horizontal padding.
  List<String> offendersIn(String path, String code) => [
    for (final call in callsOf(path, code, opener))
      if (headerChild.hasMatch(call.named['child'] ?? '') &&
          _hasHorizontal(call.named['padding'] ?? ''))
        call.where,
  ];

  // A wrapper that is on purpose, with the reason. Keyed by `path:line`'s file.
  const allowed = <String, String>{
    'lib/features/discover/presentation/widgets/discover_carousel.dart':
        'The rail pads itself by a variable inset (wider on large screens); '
        'the Padding adds only the difference to the header default, '
        '`inset - AppSpacing.lg`, so the title lands on the rail.',
  };

  test('the scan reads the old shape and finds it', () {
    const old = '''
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SectionHeader(title: 'Now playing', showChevron: false),
        ),
      ]''';
    expect(offendersIn('x.dart', codeOf(old)), hasLength(1));
    const vertical = '''
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: SectionHeader.action(title: 'T', trailing: x),
        )''';
    expect(offendersIn('x.dart', codeOf(vertical)), isEmpty);
    const other = '''
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: DomainSectionHeader(title: 'T'),
        )''';
    expect(offendersIn('x.dart', codeOf(other)), isEmpty);
  });

  test('no SectionHeader is wrapped in horizontal padding', () {
    final files = libCode();
    final all = [
      for (final file in files) ...offendersIn(file.path, file.code),
    ];
    final offenders = [
      for (final hit in all)
        if (!allowed.containsKey(hit.substring(0, hit.lastIndexOf(':')))) hit,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'SectionHeader pads its own sides. Drop the horizontal Padding (keep '
          'a vertical one), or build the header with SectionHeader.flush when '
          'the body around it is already inset.',
    );
  });

  test('every allow-list entry still wraps a header', () {
    final all = [
      for (final file in libCode()) ...offendersIn(file.path, file.code),
    ];
    for (final entry in allowed.keys) {
      expect(
        all.any((hit) => hit.startsWith('$entry:')),
        isTrue,
        reason: '$entry no longer wraps a SectionHeader; drop its entry.',
      );
    }
  });
}

/// Whether the source of a `padding:` argument pads a side.
bool _hasHorizontal(String padding) {
  if (padding.contains('horizontal:') ||
      padding.contains('left:') ||
      padding.contains('right:') ||
      padding.contains('.all(') ||
      padding.contains('.fromLTRB(')) {
    return true;
  }
  // `.symmetric(vertical: …)` and `.only(top:/bottom:)` have none; anything
  // else (a variable, a helper) is read as padded, the safe side.
  final verticalOnly = RegExp(
    r'EdgeInsets\.(?:symmetric\(\s*vertical:|only\()',
  ).hasMatch(padding);
  return !verticalOnly;
}
