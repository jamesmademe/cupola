import 'dart:async';

/// Closes a long-lived connection once nothing has used it for [after].
///
/// TrueNAS and Dockge speak over a socket each that the app keeps for as
/// long as the connection exists. Left open, a socket opened by one visit
/// stayed open until the app closed: a session held on the server and a
/// radio kept awake for pages long left. This keeps the count of what is
/// using the socket (a call in flight, between [begin] and [end]) and asks
/// [quiet] for anything else that holds it (a listener to a stream the
/// socket feeds); once neither has held it for [after], [onIdle] closes the
/// socket. The client stays usable: its next call opens a new socket, as it
/// does after any dropped connection.
class IdleClose {
  IdleClose({required this.after, required this.onIdle, bool Function()? quiet})
    : _quiet = quiet ?? _always;

  final Duration after;
  final void Function() onIdle;
  final bool Function() _quiet;

  int _busy = 0;
  Timer? _wait;
  bool _disposed = false;

  static bool _always() => true;

  /// Whether the wait for [onIdle] is running: for a test.
  bool get waiting => _wait?.isActive ?? false;

  /// Something started using the socket: no wait while it does.
  void begin() {
    _busy++;
    _wait?.cancel();
  }

  /// What [begin] started is done.
  void end() {
    if (_busy > 0) _busy--;
    settle();
  }

  /// Starts the wait if nothing holds the socket; a listener gone, a
  /// connection just opened.
  void settle() {
    if (_disposed || _busy > 0 || !_quiet()) return;
    _wait?.cancel();
    _wait = Timer(after, () {
      if (_disposed || _busy > 0 || !_quiet()) return;
      onIdle();
    });
  }

  /// Something holds the socket that [quiet] will report: stop waiting.
  void hold() => _wait?.cancel();

  void dispose() {
    _disposed = true;
    _wait?.cancel();
  }
}
