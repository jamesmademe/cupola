import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The server half of one upgraded WebSocket on the fake network.
///
/// TrueNAS speaks JSON-RPC over `wss://…/api/current` and Dockge speaks
/// Socket.IO, and both dial through `WebSocket.connect` over the pinned
/// `HttpClient`. Answering the upgrade here (a real `101`, a real
/// `Sec-WebSocket-Accept`, real frames on a detached socket) is what lets the
/// app's own clients, and the Dashboard probe that builds them directly, run
/// unmodified. A peer only ever sees whole text messages.
abstract class WebSocketPeer {
  late WebSocketLink _link;

  /// Called once the socket is open, before any client message.
  void onOpen() {}

  /// One text message from the client.
  void onText(String text);

  /// Sends one text message to the client.
  void send(String text) => _link.sendText(text);

  /// Closes the socket from the server side.
  void close([int code = 1000]) => _link.closeFromServer(code);
}

/// The key the server must answer an upgrade with (RFC 6455 §4.2.2).
String webSocketAccept(String key) => base64.encode(
  sha1.convert(utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')).bytes,
);

/// The detached socket `HttpClientResponse.detachSocket` hands `dart:io`'s
/// WebSocket: client frames in, server frames out.
///
/// Only what `_WebSocketImpl` touches is implemented: it listens once,
/// writes through `addStream`, and ends with `close` or `destroy`. Anything
/// else reaching [noSuchMethod] throws, so a new dependency on this surface
/// fails loudly instead of quietly returning null.
class WebSocketLink extends Stream<Uint8List> implements Socket {
  WebSocketLink(this._peer) {
    _peer._link = this;
    scheduleMicrotask(_peer.onOpen);
  }

  final WebSocketPeer _peer;
  final StreamController<Uint8List> _toClient = StreamController<Uint8List>();
  final _FrameReader _reader = _FrameReader();
  final Completer<void> _done = Completer<void>();

  bool get isClosed => _toClient.isClosed;

  void sendText(String text) =>
      _write(_encodeFrame(0x1, Uint8List.fromList(utf8.encode(text))));

  void closeFromServer(int code) {
    _write(_encodeFrame(0x8, Uint8List.fromList([code >> 8, code & 0xff])));
    _shut();
  }

  void _write(Uint8List bytes) {
    if (!_toClient.isClosed) _toClient.add(bytes);
  }

  void _shut() {
    if (!_toClient.isClosed) unawaited(_toClient.close());
    if (!_done.isCompleted) _done.complete();
  }

  void _receive(List<int> bytes) {
    for (final frame in _reader.add(bytes)) {
      switch (frame.opcode) {
        case 0x1:
          _peer.onText(utf8.decode(frame.payload));
        case 0x8:
          // Echo the close, as a server does, and end the stream.
          _write(_encodeFrame(0x8, frame.payload));
          _shut();
        case 0x9:
          _write(_encodeFrame(0xA, frame.payload));
        default:
          break;
      }
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _toClient.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(_receive);

  @override
  void add(List<int> data) => _receive(data);

  @override
  Future<void> close() async => _shut();

  @override
  void destroy() => _shut();

  @override
  Future<void> flush() async {}

  @override
  Future<void> get done => _done.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Frame {
  const _Frame(this.opcode, this.payload);
  final int opcode;
  final Uint8List payload;
}

/// Reassembles masked client frames from whatever chunks `dart:io` writes.
class _FrameReader {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  List<_Frame> add(List<int> chunk) {
    _buffer.add(chunk);
    var bytes = _buffer.takeBytes();
    final frames = <_Frame>[];
    while (true) {
      if (bytes.length < 2) break;
      final opcode = bytes[0] & 0x0f;
      final masked = (bytes[1] & 0x80) != 0;
      var length = bytes[1] & 0x7f;
      var offset = 2;
      if (length == 126) {
        if (bytes.length < 4) break;
        length = (bytes[2] << 8) | bytes[3];
        offset = 4;
      } else if (length == 127) {
        if (bytes.length < 10) break;
        length = 0;
        for (var i = 2; i < 10; i++) {
          length = (length << 8) | bytes[i];
        }
        offset = 10;
      }
      final maskLength = masked ? 4 : 0;
      if (bytes.length < offset + maskLength + length) break;
      final mask = bytes.sublist(offset, offset + maskLength);
      offset += maskLength;
      final payload = Uint8List.fromList(
        bytes.sublist(offset, offset + length),
      );
      if (masked) {
        for (var i = 0; i < payload.length; i++) {
          payload[i] ^= mask[i % 4];
        }
      }
      frames.add(_Frame(opcode, payload));
      bytes = Uint8List.fromList(bytes.sublist(offset + length));
    }
    _buffer.add(bytes);
    return frames;
  }
}

/// One unmasked server frame, FIN set.
Uint8List _encodeFrame(int opcode, Uint8List payload) {
  final header = BytesBuilder()..addByte(0x80 | opcode);
  final length = payload.length;
  if (length < 126) {
    header.addByte(length);
  } else if (length < 0x10000) {
    header
      ..addByte(126)
      ..addByte(length >> 8)
      ..addByte(length & 0xff);
  } else {
    header.addByte(127);
    for (var shift = 56; shift >= 0; shift -= 8) {
      header.addByte((length >> shift) & 0xff);
    }
  }
  header.add(payload);
  return header.takeBytes();
}
