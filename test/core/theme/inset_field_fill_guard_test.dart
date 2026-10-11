import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// A field that sits in a well of its own draws no fill of its own:
/// **an `InputDecoration` with `border: InputBorder.none` says
/// `filled: false`.**
///
/// The theme gives every field the quiet fill (`inputDecorationTheme`,
/// `filled: true`). A field whose container already draws the well and the
/// frame takes its border off, and unless it takes the fill off too, a second,
/// square-cornered box shows inside the rounded one: the wizard's address and
/// key fields read that way on a phone (11/10).
///
/// A source scan: the regression is one missing named argument.
void main() {
  final files = libCode();
  final opener = RegExp(r'\bInputDecoration\(');

  List<CodeCall> inset() => [
    for (final file in files)
      for (final call in callsOf(file.path, file.code, opener))
        if (call.named['border'] == 'InputBorder.none') call,
  ];

  test('lib/ has inset fields to scan', () {
    // A scanner that found nothing would pass the check below.
    expect(inset(), isNotEmpty);
  });

  test('an inset field takes the theme fill off', () {
    final offenders = [
      for (final call in inset())
        if (call.named['filled'] != 'false') call.where,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A field whose container draws the well sets filled: false beside '
          'border: InputBorder.none, or the theme fill paints a second box.',
    );
  });
}
