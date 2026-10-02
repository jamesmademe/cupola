import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/code_scan.dart';

/// The scanner the design-contract guards read `lib/` through. A guard that
/// silently saw nothing, or saw a comment as code, would pass every rule it
/// holds, so the lexer is held on the cases that fool a line scan.
void main() {
  group('codeOf', () {
    test('blanks comments and keeps every offset and every line', () {
      const source = '''
final a = 1; // AppColors.error in a trailing comment
/// AppColors.warning in a doc comment
/* AppColors.info in a block
   comment */ final b = 2;
''';
      final code = codeOf(source);
      expect(code.length, source.length);
      expect('\n'.allMatches(code).length, '\n'.allMatches(source).length);
      expect(code, isNot(contains('AppColors')));
      expect(code, contains('final a = 1;'));
      expect(code, contains('final b = 2;'));
    });

    test('blanks the text of a string and keeps its quotes', () {
      final code = codeOf("final a = 'AppColors.error is copy';");
      expect(code, "final a = '${' ' * 'AppColors.error is copy'.length}';");
    });

    test('an interpolation is code, a nested string is blanked inside it', () {
      final code = codeOf(
        r"""final a = 'x ${AppColors.error} y ${b ? 'AppColors.info' : "z"}';""",
      );
      expect(code, contains('AppColors.error'));
      expect(code, isNot(contains('AppColors.info')));
      expect(code, isNot(contains(' x ')));
    });

    test('a `//` inside a string is text, an apostrophe in a comment is not '
        'a string', () {
      final code = codeOf('''
final url = 'https://example.com/AppColors.error'; final a = AppColors.info;
// it's a comment with an apostrophe
final b = AppColors.success;
''');
      expect(code, contains('final a = AppColors.info;'));
      expect(code, contains('final b = AppColors.success;'));
      expect(code, isNot(contains('example')));
    });

    test('raw, triple-quoted and escaped strings end where Dart ends them', () {
      final code = codeOf(r"""
final a = r'AppColors.error \';
final b = '''
AppColors.warning
  across lines''';
final c = 'it\'s AppColors.info';
final d = AppColors.success;
""");
      expect(code, isNot(contains('AppColors.error')));
      expect(code, isNot(contains('AppColors.warning')));
      expect(code, isNot(contains('AppColors.info')));
      expect(code, contains('final d = AppColors.success;'));
    });
  });

  group('callsOf', () {
    List<CodeCall> calls(String source, String opener) =>
        callsOf('lib/x.dart', codeOf(source), RegExp(opener));

    test('reads the named arguments of each call, with their values', () {
      final found = calls('''
Semantics(
  button: true,
  enabled: false,
  child: Text('x'),
);
''', r'\bSemantics\(');
      expect(found, hasLength(1));
      expect(found.single.where, 'lib/x.dart:1');
      expect(found.single.named, {
        'button': 'true',
        'enabled': 'false',
        'child': "Text(' ')",
      });
    });

    test(
      'an argument of a nested call is not an argument of the outer one',
      () {
        final found = calls(
          'TextStyle(color: c, shadows: [Shadow(fontSize: 3)], '
              'foreground: Paint()..style = PaintingStyle.fill);',
          r'\bTextStyle\(',
        );
        expect(found.single.names('fontSize'), isFalse);
        expect(found.single.names('color'), isTrue);
        expect(found.single.names('shadows'), isTrue);
      },
    );

    test('a positional ternary is not a named argument', () {
      final found = calls('f(a ? b : c, d: 1);', r'\bf\(');
      expect(found.single.named, {'d': '1'});
    });

    test('a name in a string or a comment is not an argument', () {
      final found = calls('''
f(
  // fontSize: 3,
  label: 'fontSize: 3, enabled: false',
);
''', r'\bf\(');
      expect(found.single.named.keys, ['label']);
    });

    test('finds every call, each on its own line', () {
      final found = calls('''
a.copyWith(x: 1);
b.copyWith(
  fontWeight: w,
);
''', r'\bcopyWith\(');
      expect(found.map((call) => call.line), [1, 2]);
      expect(found.map((call) => call.names('fontWeight')), [false, true]);
    });
  });
}
