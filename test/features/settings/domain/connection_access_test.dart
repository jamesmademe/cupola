import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _sentinel = 'sentinel-7f3a';

void main() {
  group('the headers a connection sends', () {
    test('none sends nothing', () {
      expect(const NoAccess().headers(), isEmpty);
    });

    test('a Cloudflare service token sends its id and secret', () {
      expect(
        const CloudflareServiceToken(
          clientId: ' 1a2b.access ',
          clientSecret: 'secret',
        ).headers(),
        {
          'CF-Access-Client-Id': '1a2b.access',
          'CF-Access-Client-Secret': 'secret',
        },
      );
    });

    test('a half-filled token sends nothing, so a gateway cannot read it as '
        'a token refused', () {
      expect(
        const CloudflareServiceToken(
          clientId: 'id',
          clientSecret: '',
        ).headers(),
        isEmpty,
      );
      expect(
        const CloudflareServiceToken(clientId: '', clientSecret: 's').headers(),
        isEmpty,
      );
    });

    test('a proxy password sends Basic', () {
      expect(const ProxyPassword(username: 'matt', password: 'p:w').headers(), {
        'Authorization': 'Basic ${base64Encode(utf8.encode('matt:p:w'))}',
      });
      expect(
        const ProxyPassword(username: '', password: 'p').headers(),
        isEmpty,
      );
    });

    test('custom headers send each complete pair', () {
      expect(
        const CustomHeaders([
          (name: 'X-Proxy-Key', value: 'one'),
          (name: '', value: 'orphan'),
          (name: 'X-Empty', value: ''),
        ]).headers(),
        {'X-Proxy-Key': 'one'},
      );
    });
  });

  test('access compares by value, so a settings select settles', () {
    expect(
      const CustomHeaders([(name: 'A', value: 'b')]),
      CustomHeaders([(name: 'A', value: 'b')]),
    );
    expect(
      const CloudflareServiceToken(clientId: 'a', clientSecret: 'b'),
      isNot(const CloudflareServiceToken(clientId: 'a', clientSecret: 'c')),
    );
    const plain = ServiceInstance(id: 'radarr', service: ServiceKey.radarr);
    expect(
      plain.copyWith(
        access: const ProxyPassword(username: 'u', password: 'p'),
      ),
      isNot(plain),
    );
  });

  group('a secret is never printed', () {
    const accesses = <ConnectionAccess>[
      CloudflareServiceToken(
        clientId: '$_sentinel-id',
        clientSecret: '$_sentinel-secret',
      ),
      ProxyPassword(username: '$_sentinel-user', password: '$_sentinel-pw'),
      CustomHeaders([(name: 'X-$_sentinel', value: '$_sentinel-value')]),
    ];

    for (final access in accesses) {
      test('${access.kind.label}: not by the access, the connection or a '
          'failure', () {
        final instance = ServiceInstance(
          id: 'radarr',
          service: ServiceKey.radarr,
          url: 'https://radarr.example.com',
          credential: 'key',
          access: access,
        );
        final settings = SettingsModel(instances: [instance]);
        final gateways = [
          for (final kind in AccessGatewayKind.values)
            for (final sent in [false, true])
              AccessGatewayAnswer(
                kind: kind,
                credentialsSent: sent,
                gatewayHost: 'team.cloudflareaccess.com',
                serviceHost: 'radarr.example.com',
              ),
        ];

        final printed = [
          '$access',
          '$instance',
          '$settings',
          for (final gateway in gateways) ...[
            '$gateway',
            failureMessageOf(ServiceKey.radarr, gateway),
            connectionFailureSentence(gateway, subject: 'Radarr'),
            ...() {
              final words = describeFailureOf(ServiceKey.radarr, gateway);
              return [words.headline, words.label, ?words.remedy];
            }(),
          ],
        ].join('\n');

        expect(printed, isNot(contains(_sentinel)));
      });
    }
  });
}
