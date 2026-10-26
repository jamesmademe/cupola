import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Request extra under which a list read names the function that maps its
/// decoded JSON into models. See [ListMappingTransformer].
const kListMapExtra = 'cupola.listMapper';

/// Maps a decoded JSON list into models.
///
/// It runs where the body is decoded, so it must be sendable across an
/// isolate: a top-level function, a static tear-off, or a closure that
/// captures nothing but such values.
typedef DecodedListMapper = Object? Function(Object? decoded);

/// What a mapped list read answers with: the mapped list, wrapped so a reader
/// can tell it from the raw decoded JSON that a fake or an injected Dio answers
/// with, which the reader then maps itself.
final class MappedList {
  const MappedList(this.value);

  final Object? value;
}

/// Bodies at or above this many bytes are decoded and mapped in an isolate.
/// The same threshold Dio applies to its own decoding.
const int kListMapIsolateBytes = 50 * 1024;

/// Decodes and maps a list response inside one isolate, so the decoded tree
/// never crosses back to the main isolate to be copied into another one.
///
/// Installed by `guardedDio` in front of Dio's own transformer, and it acts
/// only on a read that asks for it with [kListMapExtra], on a 2xx JSON body.
/// Everything else goes to the inner transformer untouched, so a gateway's
/// HTML page (`text/html`) still reaches `AnswerGuardInterceptor` as the
/// `String` it recognises. A JSON-labelled body that does not decode is handed
/// to the inner transformer too, so it fails exactly as it always has.
class ListMappingTransformer extends Transformer {
  ListMappingTransformer(this._inner);

  final Transformer _inner;

  @override
  Future<String> transformRequest(RequestOptions options) =>
      _inner.transformRequest(options);

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) async {
    final mapper = options.extra[kListMapExtra];
    final status = responseBody.statusCode;
    final isJson = Transformer.isJsonMimeType(
      responseBody.headers[Headers.contentTypeHeader]?.first,
    );
    if (mapper is! DecodedListMapper ||
        options.responseType != ResponseType.json ||
        status < 200 ||
        status >= 300 ||
        !isJson) {
      return _inner.transformResponse(options, responseBody);
    }

    final bytes = await _consolidate(responseBody.stream);
    try {
      if (bytes.length < kListMapIsolateBytes) {
        return MappedList(mapper(jsonDecode(utf8.decode(bytes))));
      }
      final value = await Isolate.run(
        () => mapper(jsonDecode(utf8.decode(bytes))),
      );
      return MappedList(value);
    } catch (_) {
      // The mapper failed (a field of an unexpected type from another arr
      // version), or the body is not JSON. Either way the answer is handed back
      // as the raw decoded JSON, and the reader maps it on the main isolate, as
      // it did before this transformer existed. A mapping error then surfaces
      // as the reader's own error, not as a `DioException` that a failure
      // classifier would read as a network fault. A body that does not decode
      // goes to the inner transformer, so the answer guard names it as before.
      try {
        return jsonDecode(utf8.decode(bytes));
      } on FormatException {
        return _inner.transformResponse(
          options,
          ResponseBody.fromBytes(
            bytes,
            status,
            statusMessage: responseBody.statusMessage,
            isRedirect: responseBody.isRedirect,
            headers: responseBody.headers,
          ),
        );
      }
    }
  }
}

Future<Uint8List> _consolidate(Stream<Uint8List> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
