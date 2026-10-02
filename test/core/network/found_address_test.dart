import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/found_address.dart';

void main() {
  const seerr = 'http://nas.home.arpa:5055';

  ProposedAddress? propose(String reported, {String source = seerr}) =>
      proposeFoundAddress(reported, sourceUrl: source);

  group('a host only the source can resolve moves to the source\'s host', () {
    test('a container name, with the port the source knows', () {
      expect(
        propose('http://radarr:7878'),
        const ProposedAddress(
          url: 'http://nas.home.arpa:7878',
          basis: FoundAddressBasis.sourceHost,
        ),
      );
    });

    test('keeping the scheme and the base path the source reported', () {
      expect(
        propose('https://sonarr:9898/sonarr/')!.url,
        'https://nas.home.arpa:9898/sonarr',
      );
      expect(propose('http://lidarr')!.url, 'http://nas.home.arpa');
    });

    test('localhost and the loopback, as the source saw them', () {
      for (final reported in [
        'http://localhost:7878',
        'http://LOCALHOST:7878',
        'http://radarr.localhost:7878',
        'http://127.0.0.1:7878',
        'http://127.0.1.1:7878',
        'http://[::1]:7878',
        'http://0.0.0.0:7878',
      ]) {
        expect(
          propose(reported),
          const ProposedAddress(
            url: 'http://nas.home.arpa:7878',
            basis: FoundAddressBasis.sourceHost,
          ),
          reason: reported,
        );
      }
    });

    test("Docker's and Podman's names for their own host", () {
      expect(
        propose('http://host.docker.internal:7878')!.url,
        'http://nas.home.arpa:7878',
      );
      expect(
        propose('http://host.containers.internal:7878')!.basis,
        FoundAddressBasis.sourceHost,
      );
    });

    test('onto whatever host Cupola reaches the source at', () {
      expect(
        propose('http://radarr:7878', source: 'https://192.168.1.20:5055')!.url,
        'http://192.168.1.20:7878',
      );
      expect(
        propose('http://radarr:7878', source: 'http://[fd00::20]:5055')!.url,
        'http://[fd00::20]:7878',
      );
      expect(
        propose('http://radarr:7878', source: 'http://localhost:5055')!.url,
        'http://localhost:7878',
      );
    });
  });

  group('a real address stays as reported', () {
    test('a name with a domain, local or not', () {
      for (final reported in [
        'http://nas.home.arpa:7878',
        'http://radarr.lan:7878',
        'https://radarr.example.com',
        'http://radarr.local:7878',
      ]) {
        final proposal = propose(reported)!;
        expect(proposal.basis, FoundAddressBasis.asReported, reason: reported);
        expect(proposal.url, reported, reason: reported);
      }
    });

    test('an IP address of a real network, a Docker bridge included', () {
      expect(
        propose('http://192.168.1.20:7878')!.basis,
        FoundAddressBasis.asReported,
      );
      expect(
        propose('http://172.17.0.3:7878')!.basis,
        FoundAddressBasis.asReported,
      );
    });

    test('and so does everything when the source names no host', () {
      expect(
        propose('http://radarr:7878', source: ''),
        const ProposedAddress(
          url: 'http://radarr:7878',
          basis: FoundAddressBasis.asReported,
        ),
      );
    });
  });

  test('two found services can end on one proposed address', () {
    // Radarr and Radarr 4K both listen on 7878 inside their containers; the
    // proposal for each is the same, and only a key says which is there.
    expect(propose('http://radarr:7878'), propose('http://radarr-4k:7878'));
  });

  test('an address with no host proposes nothing', () {
    expect(propose(''), isNull);
    expect(propose('   '), isNull);
  });

  test('a credential written into an address is left out', () {
    expect(
      propose('http://admin:hunter2@radarr:7878')!.url,
      'http://nas.home.arpa:7878',
    );
    expect(
      propose(
        'http://radarr:7878',
        source: 'http://admin:hunter2@nas.home.arpa:5055',
      )!.url,
      'http://nas.home.arpa:7878',
    );
  });

  test('names its host and port for a sentence', () {
    expect(propose('http://radarr:7878')!.hostAndPort, 'nas.home.arpa:7878');
    expect(
      propose('https://radarr.example.com')!.hostAndPort,
      'radarr.example.com:443',
    );
    expect(
      propose(
        'http://radarr:7878',
        source: 'http://[fd00::20]:5055',
      )!.hostAndPort,
      '[fd00::20]:7878',
    );
  });

  test(
    'says when trying a key there would cross the internet in the clear',
    () {
      expect(propose('http://radarr:7878')!.sendsKeyInClear, isFalse);
      expect(
        propose(
          'http://radarr:7878',
          source: 'https://seerr.example.net',
        )!.sendsKeyInClear,
        isTrue,
      );
      expect(
        propose(
          'https://radarr:7878',
          source: 'https://seerr.example.net',
        )!.sendsKeyInClear,
        isFalse,
      );
    },
  );

  group('foundHostIsLocalToSource', () {
    test('reads the host alone', () {
      expect(foundHostIsLocalToSource('radarr'), isTrue);
      expect(foundHostIsLocalToSource('radarr_4k'), isTrue);
      expect(foundHostIsLocalToSource('[::1]'), isTrue);
      expect(foundHostIsLocalToSource('::'), isTrue);
      expect(foundHostIsLocalToSource('radarr.'), isTrue);
      expect(foundHostIsLocalToSource('gateway.docker.internal'), isTrue);
      expect(foundHostIsLocalToSource('nas.internal'), isFalse);
      expect(foundHostIsLocalToSource('10.0.0.5'), isFalse);
      expect(foundHostIsLocalToSource(''), isFalse);
    });
  });
}
