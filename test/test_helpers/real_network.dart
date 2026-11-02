import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lets every test of the enclosing `main` (or group) reach a real server on
/// this machine, with no `HttpOverrides` in between.
///
/// The Flutter test binding installs process-wide `HttpOverrides` that answer
/// every request with a 400, as soon as any `testWidgets` is declared. A file
/// of plain `test`s alone in its isolate never meets them, and a test that
/// binds an `HttpServer` on the loopback works by accident of running there.
/// In a bundle (`tool/test_bundles`), the files of a folder share one
/// isolate: a test that needs the real network says so with this, and the
/// overrides come back when it ends.
void useRealNetwork() {
  setUp(() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
  });
}
