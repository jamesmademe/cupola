import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// The lock on what one device hands another: AES-256-GCM under a key
/// derived from the link's 32 bytes, and the one path the sending server
/// answers, derived from the same bytes.
///
/// Two keys from one secret, through HKDF-SHA256 with a different `info`
/// each: the path is said aloud on the network (it is in the request line),
/// so it must tell nothing about the key that opens the package. The
/// associated data names the protocol and its version, so a package sealed
/// for anything else does not open as one of these.
///
/// The pure Dart implementations, chosen by name rather than through
/// `Cryptography.instance`: what seals here must open on every platform the
/// same way, whatever plugin a later build registers.
abstract final class PairCipher {
  /// Names the protocol in the derivation and in the associated data.
  static const protocol = 'cupola-pair-v1';

  static final _aes = DartAesGcm.with256bits();
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// A fresh 32-byte link key, from the platform's secure generator.
  static Uint8List newKey([Random? random]) {
    final rng = random ?? Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  /// [clear] sealed under [linkKey]: the nonce, the cipher text and the tag,
  /// one after the other.
  static Future<Uint8List> seal(Uint8List linkKey, List<int> clear) async {
    final box = await _aes.encrypt(
      clear,
      secretKey: await _derive(linkKey, 'package', 32),
      aad: utf8.encode(protocol),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// What [sealed] holds, or a [PairSealBroken] when it was not sealed under
  /// [linkKey] for this protocol, or was changed on the way.
  static Future<Uint8List> open(Uint8List linkKey, List<int> sealed) async {
    if (sealed.length < _nonceLength + _macLength) throw const PairSealBroken();
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await _aes.decrypt(
        box,
        secretKey: await _derive(linkKey, 'package', 32),
        aad: utf8.encode(protocol),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const PairSealBroken();
    }
  }

  /// The one path the sending server answers for [linkKey]: a slash and 22
  /// characters (128 bits). Someone on the network without the code cannot
  /// name it, so cannot even fetch the sealed package.
  static Future<String> pathOf(Uint8List linkKey) async {
    final bytes = await (await _derive(linkKey, 'path', 16)).extractBytes();
    return '/${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  static Future<SecretKey> _derive(
    Uint8List linkKey,
    String purpose,
    int length,
  ) => DartHkdf(hmac: const DartHmac(DartSha256()), outputLength: length)
      .deriveKey(
        secretKey: SecretKeyData(linkKey),
        nonce: utf8.encode(protocol),
        info: utf8.encode(purpose),
      );
}

/// A sealed package that did not open: another key, another protocol, or
/// bytes changed on the way.
final class PairSealBroken implements Exception {
  const PairSealBroken();

  @override
  String toString() => 'PairSealBroken';
}
