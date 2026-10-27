import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/header_action_row.dart';

void main() {
  group('HeaderActionRow.buttonHeight', () {
    test('clears the platform touch-target minimums', () {
      // 44pt is iOS' floor and the number this codebase writes down for itself
      // on the detail back button; 48dp is Android's. One shared constant has to
      // clear the larger of the two. It used to be 42.
      expect(HeaderActionRow.buttonHeight, greaterThanOrEqualTo(44));
      expect(HeaderActionRow.buttonHeight, greaterThanOrEqualTo(48));
    });
  });
}
