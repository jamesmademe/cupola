import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/presentation/dockge_provider.dart';

const int _maxChars = 64 * 1024;

void main() {
  group('TerminalTail keeps its promised 64 KiB cap', () {
    test('a stream that never sends a newline is still bounded', () {
      // The defect this covers: the trim walked forward to the next `\n` and
      // gave up when there was none, so `cut` stayed 0 and the buffer grew
      // for as long as the socket kept talking. A hostile Dockge needs only
      // to withhold one byte to exhaust the device.
      final tail = TerminalTail();
      var text = '';
      for (var i = 0; i < 40; i++) {
        text = tail.append('x' * 4096);
      }
      expect(text.length, lessThanOrEqualTo(_maxChars));
    });

    test('carriage-return progress output is bounded too', () {
      // Not only the hostile case: `docker compose pull` draws its progress
      // with `\r`, so an ordinary pull on a large stack reaches the same path.
      final tail = TerminalTail();
      var text = '';
      for (var i = 0; i < 4000; i++) {
        text = tail.append('\rPulling layer $i: 45.2MB/128.0MB');
      }
      expect(text.length, lessThanOrEqualTo(_maxChars));
      expect(text, contains('Pulling layer 3999'));
    });

    test('one chunk larger than the whole buffer is clamped', () {
      final tail = TerminalTail();
      final text = tail.append('y' * (_maxChars * 3));
      expect(text.length, lessThanOrEqualTo(_maxChars));
      expect(text, endsWith('y'));
    });

    test('ordinary line output still cuts on a line boundary', () {
      // The hard cap is a floor, not a replacement: while there are newlines
      // to cut on, the first visible row stays a whole line.
      final tail = TerminalTail();
      var text = '';
      for (var i = 0; i < 3000; i++) {
        text = tail.append('line $i\n');
      }
      expect(text.length, lessThanOrEqualTo(_maxChars));
      expect(text, startsWith('line '));
      expect(text, endsWith('line 2999\n'));
    });

    test('output below the cap is returned untouched', () {
      final tail = TerminalTail();
      expect(tail.append('container started\n'), 'container started\n');
      expect(tail.append('ready\n'), 'container started\nready\n');
    });
  });
}
