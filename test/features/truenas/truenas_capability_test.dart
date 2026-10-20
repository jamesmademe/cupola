import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/models/data_protection.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

import '../../test_helpers/fixtures.dart';
import '../../test_helpers/settings_scope.dart';

/// The fixtures here are transcribed from the middleware source
/// (`plugins/auth.py` `me`, `plugins/account_/privilege.py`), not captured
/// from a live server: they prove Cupola reads the shape as transcribed. The
/// roles carry the `{"$set": [...]}` envelope the middleware's JSON encoder
/// writes for a set, as the TrueNAS web UI reads them.
class _FakeNas extends TrueNasWsClient {
  _FakeNas(this.answers) : super(baseUrl: 'https://nas.local', apiKey: 'k');

  final Map<String, Object? Function()> answers;
  final List<String> calls = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    calls.add(method);
    final answer = answers[method];
    if (answer == null) throw const TrueNasException('no such method');
    return answer();
  }
}

Future<CapabilityGrant> _probe(
  Object? Function() me, {
  String version = 'TrueNAS-SCALE-25.04.1',
  List<Map<String, Object?>> services = const [],
}) async {
  final nas = _FakeNas({
    'auth.me': me,
    'system.version': () => version,
    'service.query': () => services,
  });
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...await settingsScopeOverrides(configured: const [ServiceKey.truenas]),
      truenasClientProvider.overrideWithValue(nas),
    ],
  );
  addTearDown(container.dispose);
  return container.read(connectionCapabilityProvider('truenas').future);
}

const _services = [
  {'id': 1, 'service': 'cifs', 'state': 'RUNNING'},
  {'id': 2, 'service': 'nfs', 'state': 'STOPPED'},
  {'id': 3, 'service': 'ssh', 'state': 'RUNNING'},
];

void main() {
  group('the probe over auth.me', () {
    test('FULL_ADMIN writes everything', () async {
      expect(
        await _probe(() => jsonFixtureMap('truenas/auth_me_full_admin.json')),
        const CapabilityGrant.readWrite(),
      );
    });

    test('READONLY_ADMIN, expanded to *_READ, writes nothing', () async {
      expect(
        await _probe(
          () => jsonFixtureMap('truenas/auth_me_readonly_admin.json'),
          services: _services,
        ),
        const CapabilityGrant.readOnly(),
      );
    });

    test(
      'SHARING_ADMIN writes the shares, their services and datasets',
      () async {
        expect(
          await _probe(
            () => jsonFixtureMap('truenas/auth_me_sharing_admin.json'),
            services: _services,
          ),
          const CapabilityGrant.partial({
            'smb',
            'nfs',
            'iscsi',
            'datasetWrite',
            'service:cifs',
            'service:nfs',
          }),
        );
      },
    );

    test('roles arrive in the {"\$set": [...]} envelope or as a list', () {
      // A real 25.10 server wraps the set; the parser must not read that as
      // "no roles", which held every write back behind the unanswered banner.
      Map<String, Object?> me(Object roles) => {
        'privilege': {'roles': roles},
      };
      expect(
        trueNasRolesFromMe(
          me({
            r'$set': ['full_admin'],
          }),
        ),
        {trueNasFullAdmin},
      );
      expect(trueNasRolesFromMe(me(['FULL_ADMIN'])), {trueNasFullAdmin});
      expect(trueNasRolesFromMe(me({'other': 1})), isNull);
    });

    test('an answer with no privilege is unanswered', () async {
      expect(
        await _probe(() => jsonFixtureMap('truenas/auth_me_no_privilege.json')),
        const CapabilityGrant.unanswered(),
      );
    });

    test(
      'a server that refuses auth.me (24.10 with a key) is unanswered',
      () async {
        expect(
          await _probe(() => throw const TrueNasException('Not authenticated')),
          const CapabilityGrant.unanswered(),
        );
      },
    );
  });

  group('every area maps from each of its role names', () {
    for (final area in TrueNasCapabilityArea.values) {
      for (final version in const [
        TrueNasVersion(25, 4),
        TrueNasVersion(25, 10),
      ]) {
        final roles = area.grantedBy(version);
        test('${area.key} on $version', () {
          for (final role in roles) {
            final grant = trueNasGrantFor({role}, version: version);
            expect(
              grant.scopeFor(area.key),
              CapabilityScope.readWrite,
              reason: '$role should grant ${area.key}',
            );
          }
          // And nothing but its own roles or full admin grants it.
          expect(
            trueNasGrantFor({'SOME_READ'}, version: version).scopeFor(area.key),
            CapabilityScope.readOnly,
          );
          expect(
            trueNasGrantFor({
              trueNasFullAdmin,
            }, version: version).scopeFor(area.key),
            CapabilityScope.readWrite,
          );
        });
      }
    }

    test('three areas are full admin only on 25.04', () {
      for (final area in [
        TrueNasCapabilityArea.power,
        TrueNasCapabilityArea.mailSend,
        TrueNasCapabilityArea.rsyncRun,
      ]) {
        expect(area.grantedBy(const TrueNasVersion(25, 4)), isEmpty);
      }
      // 25.10 declared roles for two of them.
      expect(
        TrueNasCapabilityArea.mailSend.grantedBy(const TrueNasVersion(25, 10)),
        {'MAIL_WRITE'},
      );
      expect(
        TrueNasCapabilityArea.rsyncRun.grantedBy(const TrueNasVersion(25, 10)),
        {'SNAPSHOT_TASK_WRITE'},
      );
      expect(
        TrueNasCapabilityArea.power.grantedBy(const TrueNasVersion(25, 10)),
        isEmpty,
      );
    });

    test('an unknown version gets the stricter 25.04 rules', () {
      expect(
        trueNasGrantFor({'MAIL_WRITE'}).scopeFor('mailSend'),
        CapabilityScope.readOnly,
      );
    });

    test('dataset delete is its own role', () {
      expect(
        trueNasGrantFor({'DATASET_WRITE'}).scopeFor('datasetDelete'),
        CapabilityScope.readOnly,
      );
    });
  });

  group('service.*: the in-body check', () {
    test('the matching sharing role changes its service only', () {
      final grant = trueNasGrantFor(
        {'SHARING_SMB_WRITE'},
        services: const ['cifs', 'nfs', 'ssh'],
      );
      expect(grant.scopeFor('service:cifs'), CapabilityScope.readWrite);
      expect(grant.scopeFor('service:nfs'), CapabilityScope.readOnly);
      expect(grant.scopeFor('service:ssh'), CapabilityScope.readOnly);
    });

    test('SERVICE_WRITE works from 25.10 and not on 25.04', () {
      // 25.04 checks a role that does not exist (`SERVICES_WRITE`).
      expect(
        trueNasMayWriteService('ssh', {
          'SERVICE_WRITE',
        }, const TrueNasVersion(25, 4)),
        isFalse,
      );
      expect(
        trueNasMayWriteService('ssh', {
          'SERVICE_WRITE',
        }, const TrueNasVersion(25, 10)),
        isTrue,
      );
      expect(trueNasMayWriteService('ssh', {'SERVICE_WRITE'}, null), isFalse);
    });
  });

  group('data protection picks the area per task', () {
    TrueNasProtectionTask task(
      TrueNasTaskKind kind, [
      Map<String, dynamic> json = const {},
    ]) => TrueNasProtectionTask.fromJson(kind, {'id': 1, ...json});

    test('run and write differ where the middleware differs', () {
      expect(
        task(TrueNasTaskKind.rsync).runArea,
        TrueNasCapabilityArea.rsyncRun,
      );
      expect(
        task(TrueNasTaskKind.rsync).writeArea,
        TrueNasCapabilityArea.rsyncTask,
      );
      expect(
        task(TrueNasTaskKind.scrub).runArea,
        TrueNasCapabilityArea.scrubRun,
      );
      expect(
        task(TrueNasTaskKind.scrub).writeArea,
        TrueNasCapabilityArea.scrubTask,
      );
    });

    test('a PULL replication needs the pull role', () {
      final pull = task(TrueNasTaskKind.replication, {'direction': 'PULL'});
      final push = task(TrueNasTaskKind.replication, {'direction': 'PUSH'});
      expect(pull.isPull, isTrue);
      expect(pull.runArea, TrueNasCapabilityArea.replicationPull);
      expect(push.runArea, TrueNasCapabilityArea.replication);
    });
  });
}
