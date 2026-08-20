import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/local_network_access.dart';

/// The contract with the host side of the local-network permission.
///
/// Two properties matter more than the mapping itself. The probe must never ask
/// the OS about an address that is not on the local network — asking is what puts
/// a permission alert on screen, and doing that because a public server timed out
/// would be a worse bug than the one this exists to fix. And nothing here may
/// throw: a permission check that can break a connection test is worse than no
/// permission check at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answerWith(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(LocalNetworkPermission.channel, handler);
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        LocalNetworkPermission.channel,
        null,
      ),
    );
  }

  setUp(() {
    // Pinned so the platform gate is not the host's own OS: these cases are
    // about the wiring, and on a Linux runner every one of them would otherwise
    // short-circuit to `unrestricted`.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('LocalNetworkPermission.resolve', () {
    test('maps every verdict the host can return', () async {
      final verdicts = <String, LocalNetworkAccess>{
        'granted': LocalNetworkAccess.granted,
        'just_granted': LocalNetworkAccess.justGranted,
        'denied': LocalNetworkAccess.denied,
        'unrestricted': LocalNetworkAccess.unrestricted,
        // Anything unrecognised claims nothing rather than guessing.
        'something-new': LocalNetworkAccess.unknown,
      };
      for (final entry in verdicts.entries) {
        answerWith((_) async => entry.key);
        expect(
          await LocalNetworkPermission.resolve(),
          entry.value,
          reason: 'host said ${entry.key}',
        );
      }
    });

    test('hands the host how long it may take', () async {
      MethodCall? received;
      answerWith((call) async {
        received = call;
        return 'granted';
      });

      await LocalNetworkPermission.resolve(timeout: const Duration(seconds: 3));

      expect(received?.method, 'resolve');
      // The host owns the deadline so it can tear its own probe down rather than
      // leaving a listener and a browser running behind an abandoned call.
      expect(received?.arguments, {'timeoutMs': 3000});
    });

    test('holds no state between callers', () async {
      // Both obvious pieces of state were tried and both were bugs. Caching a
      // verdict outlives the user revoking the permission in Settings; sharing
      // one in-flight future means a widget tree disposed mid-probe leaves every
      // later caller in the process awaiting a promise nothing will ever
      // complete. The host coalesces concurrent probes instead — it can answer
      // every waiter at once and cancel its own listener.
      var calls = 0;
      answerWith((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'denied';
      });

      final verdicts = await Future.wait([
        LocalNetworkPermission.resolve(),
        LocalNetworkPermission.resolve(),
        LocalNetworkPermission.resolve(),
      ]);

      expect(calls, 3);
      expect(verdicts, everyElement(LocalNetworkAccess.denied));
    });

    test(
      'does not remember a verdict, because the user can revoke it',
      () async {
        var calls = 0;
        answerWith((_) async {
          calls++;
          return 'granted';
        });

        await LocalNetworkPermission.resolve();
        await LocalNetworkPermission.resolve();

        expect(calls, 2);
      },
    );

    test('reads an unwired platform as unrestricted', () async {
      // Desktop Linux and Windows gate nothing, and neither does a test binding
      // with no handler registered.
      expect(
        await LocalNetworkPermission.resolve(),
        LocalNetworkAccess.unrestricted,
      );
    });

    test('a host that fails claims nothing', () async {
      answerWith((_) async => throw PlatformException(code: 'boom'));
      expect(
        await LocalNetworkPermission.resolve(),
        LocalNetworkAccess.unknown,
      );
    });

    test('a host that never answers claims nothing', () async {
      // Not a hypothetical: a channel with nothing listening does not fail, it
      // stays silent — which is exactly what a binding with no mock handler does.
      // A permission check that can hang is a connection test that never
      // finishes, so the deadline is enforced here as well as by the host.
      answerWith((_) => Completer<Object?>().future);

      expect(
        await LocalNetworkPermission.resolve(
          timeout: const Duration(milliseconds: 10),
        ),
        LocalNetworkAccess.unknown,
      );
    });
  });

  group('probeLocalNetworkAccess', () {
    test('never asks the OS about an address off the local network', () async {
      answerWith((call) async {
        fail('asked the OS about a public address: ${call.method}');
      });

      expect(
        await probeLocalNetworkAccess('https://1.1.1.1'),
        LocalNetworkAccess.unrestricted,
      );
      // Loopback is exempt from the gate on every platform.
      expect(
        await probeLocalNetworkAccess('http://127.0.0.1:7878'),
        LocalNetworkAccess.unrestricted,
      );
    });

    test('asks about an address on the local network', () async {
      answerWith((_) async => 'denied');
      expect(
        await probeLocalNetworkAccess('https://192.168.1.10:7878'),
        LocalNetworkAccess.denied,
      );
    });

    test('skips platforms with no such gate', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      answerWith(
        (call) async => fail(
          'asked Linux about a permission it has '
          'never had: ${call.method}',
        ),
      );

      expect(
        await probeLocalNetworkAccess('https://192.168.1.10:7878'),
        LocalNetworkAccess.unrestricted,
      );
    });
  });

  group('LocalNetworkPermission.openSettings', () {
    test('reports whether the host got there', () async {
      answerWith((_) async => true);
      expect(await LocalNetworkPermission.openSettings(), isTrue);

      answerWith((_) async => throw PlatformException(code: 'no-activity'));
      expect(await LocalNetworkPermission.openSettings(), isFalse);
    });
  });

  group('LocalNetworkPermission.remedy', () {
    test('names the route in the words the running OS uses', () {
      expect(LocalNetworkPermission.remedy, contains('Local Network'));

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(LocalNetworkPermission.remedy, contains('System Settings'));

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(LocalNetworkPermission.remedy, contains('local network'));
    });
  });
}
