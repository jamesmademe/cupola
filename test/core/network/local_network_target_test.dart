import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/local_network_target.dart';

/// The gate this classifier guards is the local-network permission, and getting
/// it wrong is expensive in both directions: a false positive raises an OS
/// permission alert because a public server was slow, and a false negative
/// leaves the user re-typing a hostname the OS never let Cupola dial.
void main() {
  group('localNetworkHostVerdict', () {
    test('reads the private ranges as local', () {
      expect(localNetworkHostVerdict('192.168.1.10'), isTrue);
      expect(localNetworkHostVerdict('10.0.0.5'), isTrue);
      expect(localNetworkHostVerdict('172.16.4.1'), isTrue);
      expect(localNetworkHostVerdict('172.31.255.254'), isTrue);
      // Link-local: what a NAS gives itself when DHCP never answered.
      expect(localNetworkHostVerdict('169.254.7.7'), isTrue);
    });

    test('keeps the neighbours of those ranges out', () {
      // One octet outside 172.16/12 in each direction — the range most often
      // mis-implemented as "anything starting with 172".
      expect(localNetworkHostVerdict('172.15.0.1'), isFalse);
      expect(localNetworkHostVerdict('172.32.0.1'), isFalse);
      expect(localNetworkHostVerdict('8.8.8.8'), isFalse);
    });

    test('does not claim carrier-NAT space', () {
      // 100.64/10 is where Tailscale lives, and Tailscale traffic leaves through
      // a tunnel the local network permission has no say over. Calling it local
      // would blame that permission for every failure on a remote connection.
      expect(localNetworkHostVerdict('100.64.0.1'), isFalse);
      expect(localNetworkHostVerdict('100.101.102.103'), isFalse);
    });

    test('exempts loopback, which is never gated', () {
      expect(localNetworkHostVerdict('127.0.0.1'), isFalse);
      expect(localNetworkHostVerdict('::1'), isFalse);
      expect(localNetworkHostVerdict('localhost'), isFalse);
    });

    test('reads IPv6 link-local and unique-local as local', () {
      expect(localNetworkHostVerdict('fe80::1'), isTrue);
      expect(localNetworkHostVerdict('[fe80::1]'), isTrue);
      expect(localNetworkHostVerdict('fd12:3456::1'), isTrue);
      expect(localNetworkHostVerdict('2606:4700::1111'), isFalse);
    });

    test('follows an IPv4 destination wearing an IPv6 address', () {
      expect(localNetworkHostVerdict('::ffff:192.168.1.10'), isTrue);
      expect(localNetworkHostVerdict('::ffff:8.8.8.8'), isFalse);
    });

    test('reads the names that can only be on the LAN', () {
      expect(localNetworkHostVerdict('nas.local'), isTrue);
      expect(localNetworkHostVerdict('radarr.lan'), isTrue);
      expect(localNetworkHostVerdict('sonarr.internal'), isTrue);
      expect(localNetworkHostVerdict('nas.home.arpa'), isTrue);
      // A single label — a router's own DNS, or a Compose service name.
      expect(localNetworkHostVerdict('radarr'), isTrue);
    });

    test('defers on a name only DNS can place', () {
      // Split-horizon DNS: the same name is a 192.168 address at home and
      // nothing at all anywhere else. Guessing either way here is what the null
      // exists to avoid.
      expect(localNetworkHostVerdict('nas.example.com'), isNull);
    });
  });

  group('targetIsOnLocalNetwork', () {
    Future<List<InternetAddress>> never(String host) async =>
        throw StateError('resolved $host, which the name alone answers');

    test('answers from the address without resolving anything', () async {
      expect(
        await targetIsOnLocalNetwork('https://nas.local:8989', lookup: never),
        isTrue,
      );
      // Scheme-less, exactly as the form accepts it.
      expect(
        await targetIsOnLocalNetwork('192.168.1.5:7878', lookup: never),
        isTrue,
      );
    });

    test('resolves a name that could be either', () async {
      expect(
        await targetIsOnLocalNetwork(
          'https://nas.example.com:8989',
          lookup: (_) async => [InternetAddress('192.168.1.20')],
        ),
        isTrue,
      );
      expect(
        await targetIsOnLocalNetwork(
          'https://seerr.example.com',
          lookup: (_) async => [InternetAddress('203.0.113.9')],
        ),
        isFalse,
      );
    });

    test('a name that will not resolve is not claimed as local', () async {
      // The permission story is only ever offered as an explanation. Offering it
      // for a host nothing can even resolve trades one wrong answer for another.
      expect(
        await targetIsOnLocalNetwork(
          'https://typo.example.com',
          lookup: (_) async => throw const SocketException('no such host'),
        ),
        isFalse,
      );
    });

    test('a resolver that hangs does not hold up the verdict', () async {
      expect(
        await targetIsOnLocalNetwork(
          'https://slow.example.com',
          lookup: (_) => Future.delayed(
            const Duration(seconds: 30),
            () => [InternetAddress('192.168.1.20')],
          ),
          lookupTimeout: const Duration(milliseconds: 20),
        ),
        isFalse,
      );
    });
  });
}
