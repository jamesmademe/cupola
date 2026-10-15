import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cupola/features/pairing/domain/pair_cipher.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';

/// Why a package did not arrive.
enum PairFetchFailure {
  /// Nothing answered at the link's address: another network, most often.
  unreachable,

  /// The code's two minutes are over.
  expired,

  /// Something arrived and did not open, or did not read as a package.
  unreadable,

  /// A package a later Cupola wrote.
  newer,
}

/// A package that did not arrive, and why.
final class PairFetchException implements Exception {
  const PairFetchException(this.failure);

  final PairFetchFailure failure;

  @override
  String toString() => 'PairFetchException(${failure.name})';
}

/// Fetches the package [link] names from the device that opened it, opens it
/// and reads it. Throws a [PairFetchException] for every way it can fail.
///
/// Plain `http` to the sending device's home network address and nowhere
/// else ([PairLink.fromQuery] reads no other): the package is sealed, so the
/// network sees bytes it cannot open, and a gateway, a proxy or a certificate
/// would only stand between two devices on the same Wi-Fi. No system proxy is
/// asked, and no more than [PairPackage.maxBytes] is read.
///
/// A connection that fails before the code's closing time reads as
/// [PairFetchFailure.unreachable]; after it, as
/// [PairFetchFailure.expired]: the sending device's clock, in the link, is
/// what tells the two apart.
Future<PairPackage> fetchPairPackage(
  PairLink link, {
  HttpClient? client,
  Duration timeout = const Duration(seconds: 5),
  DateTime Function() now = DateTime.now,
}) async {
  PairFetchException failed(PairFetchFailure failure) =>
      PairFetchException(failure);
  PairFetchException unanswered() => failed(
    link.hasClosedBy(now())
        ? PairFetchFailure.expired
        : PairFetchFailure.unreachable,
  );

  if (link.hasClosedBy(now())) throw failed(PairFetchFailure.expired);
  final http = client ?? HttpClient();
  http
    ..connectionTimeout = timeout
    ..findProxy = ((_) => 'DIRECT');
  try {
    final request = await http
        .getUrl(
          Uri(
            scheme: 'http',
            host: link.host.address,
            port: link.port,
            path: await PairCipher.pathOf(link.key),
          ),
        )
        .timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().catchError((_) {});
      throw unanswered();
    }
    final sealed = await _readCapped(
      response,
      PairPackage.maxBytes,
    ).timeout(timeout * 2);
    final clear = await PairCipher.open(link.key, sealed);
    return PairPackage.decode(clear);
  } on PairFetchException {
    rethrow;
  } on PairSealBroken {
    throw failed(PairFetchFailure.unreadable);
  } on PairPackageNewer {
    throw failed(PairFetchFailure.newer);
  } on FormatException {
    throw failed(PairFetchFailure.unreadable);
  } on SocketException {
    throw unanswered();
  } on TimeoutException {
    throw unanswered();
  } on HttpException {
    throw unanswered();
  } finally {
    if (client == null) http.close(force: true);
  }
}

Future<Uint8List> _readCapped(Stream<List<int>> body, int cap) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in body) {
    bytes.add(chunk);
    if (bytes.length > cap) throw const FormatException('too large');
  }
  return bytes.takeBytes();
}
