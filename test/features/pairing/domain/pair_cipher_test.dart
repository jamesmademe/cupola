import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/pairing/domain/pair_cipher.dart';

void main() {
  final key = PairCipher.newKey(Random(1));
  final other = PairCipher.newKey(Random(2));
  final clear = utf8.encode('{"v":1}');

  test('opens what it sealed', () async {
    final sealed = await PairCipher.seal(key, clear);
    expect(await PairCipher.open(key, sealed), clear);
  });

  test('never seals the same thing twice the same way', () async {
    final a = await PairCipher.seal(key, clear);
    final b = await PairCipher.seal(key, clear);
    expect(a, isNot(b));
    expect(a.length, 12 + clear.length + 16);
  });

  test('does not open under another key', () async {
    final sealed = await PairCipher.seal(key, clear);
    await expectLater(
      PairCipher.open(other, sealed),
      throwsA(isA<PairSealBroken>()),
    );
  });

  test('does not open a package changed on the way', () async {
    final sealed = await PairCipher.seal(key, clear);
    for (final at in [0, 12, sealed.length - 1]) {
      final changed = Uint8List.fromList(sealed)..[at] ^= 1;
      await expectLater(
        PairCipher.open(key, changed),
        throwsA(isA<PairSealBroken>()),
        reason: 'byte $at',
      );
    }
    await expectLater(
      PairCipher.open(key, sealed.sublist(0, 20)),
      throwsA(isA<PairSealBroken>()),
    );
  });

  test('names a path that tells nothing of the package key', () async {
    final path = await PairCipher.pathOf(key);
    expect(path, matches(RegExp(r'^/[A-Za-z0-9_-]{22}$')));
    expect(await PairCipher.pathOf(key), path);
    expect(await PairCipher.pathOf(other), isNot(path));
  });

  test('draws a fresh key of 32 bytes each time', () {
    final a = PairCipher.newKey();
    final b = PairCipher.newKey();
    expect(a, hasLength(32));
    expect(a, isNot(b));
  });
}
