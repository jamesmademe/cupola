import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_capability.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';
import '../../../test_helpers/settings_scope.dart';

UnraidClient _client(CapturingHttpAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://unraid.local'))
    ..httpClientAdapter = adapter;
  return UnraidClient(url: 'https://unraid.local', apiKey: 'K', dio: dio);
}

Future<CapabilityGrant> _probe(String fixture) async {
  final adapter = CapturingHttpAdapter(
    response: jsonFixtureMap('unraid/$fixture.json'),
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...await settingsScopeOverrides(configured: const [ServiceKey.unraid]),
      unraidClientProvider.overrideWithValue(_client(adapter)),
    ],
  );
  addTearDown(container.dispose);
  return container.read(connectionCapabilityProvider('unraid').future);
}

void main() {
  group('the probe, end to end over the client', () {
    test('an ADMIN key writes everything', () async {
      expect(await _probe('me_admin'), const CapabilityGrant.readWrite());
    });

    test('a VIEWER key with no explicit write is read-only', () async {
      expect(await _probe('me_viewer'), const CapabilityGrant.readOnly());
    });

    test('an explicit UPDATE_ANY on VMs writes VMs and only VMs', () async {
      expect(
        await _probe('me_vms_only'),
        const CapabilityGrant.partial({'vms'}),
      );
    });

    test('UPDATE_OWN is not a write the resolvers accept', () async {
      // The regression the parser fix closes: `UPDATE_OWN` read as a write and
      // drew live a control every tap of which would be refused.
      expect(await _probe('me_update_own'), const CapabilityGrant.readOnly());
    });

    test('a key that cannot even ask is unanswered, never read-only', () async {
      // A bad key is a broken connection, reported by the health path; the
      // banner never claims "read-only" for a key that cannot read.
      expect(
        await _probe('error_unauthenticated'),
        const CapabilityGrant.unanswered(),
      );
    });

    test('an answer without roles says nothing', () {
      expect(
        unraidGrantFor(UnraidCapabilities.fromJson(const {})),
        const CapabilityGrant.unanswered(),
      );
    });
  });

  group('the refusal shape', () {
    test('FORBIDDEN on 200 is a permission refusal, not a bad key', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('unraid/error_forbidden.json'),
      );
      final error = await _client(adapter)
          .runVmAction('vm:1', UnraidVmAction.stop)
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<UnraidException>());
      final unraid = error! as UnraidException;
      expect(unraid.forbidden, isTrue);
      expect(unraid.reason, isNot(ServiceFailureReason.unauthorized));
      expect(isPermissionRefusal(unraid), isTrue);
    });

    test('UNAUTHENTICATED is a bad key, never a refusal', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('unraid/error_unauthenticated.json'),
      );
      final error = await _client(
        adapter,
      ).getInfo().then<Object?>((_) => null, onError: (Object e) => e);

      final unraid = error! as UnraidException;
      expect(unraid.forbidden, isFalse);
      expect(unraid.reason, ServiceFailureReason.unauthorized);
      expect(isPermissionRefusal(unraid), isFalse);
    });

    test('an error with no code still reads its message', () {
      final unraid = unraidGraphQlError({'message': 'Invalid API key'});
      expect(unraid.forbidden, isFalse);
      expect(unraid.reason, ServiceFailureReason.unauthorized);
    });
  });
}
