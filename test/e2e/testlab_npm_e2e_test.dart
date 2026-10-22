@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';

/// The NPM rows of the flow catalogue, I-04 to I-08, read and written through
/// the app's own client against the real container on 127.0.0.1:8181.
///
/// The lab is arranged by the `npm-lab` scenario, which this file applies in
/// `setUpAll` and takes apart again in `tearDownAll`:
///
/// ```
/// python3 test/e2e/testlab/testlab.py scenario apply npm-lab
/// python3 test/e2e/testlab/testlab.py scenario teardown npm-lab
/// ```
///
/// It leaves two proxy hosts in front of real lab services:
/// `cupola-lab.test` for Radarr, carrying the expiring certificate and a
/// working custom block, and `cupola-alt.test` for Dockge behind an access
/// list. Both are named in `state/npm-lab.json`, never guessed here, and both
/// are removed by the scenario's teardown, so a failed test cannot leave a
/// broken nginx block behind.
///
/// Two rows have a declared limit rather than a green path:
///
/// * **I-06's success arm.** NPM renews only Let's Encrypt certificates, and a
///   Let's Encrypt one cannot exist without an ACME endpoint and a domain the
///   lab does not own. The test proves the amber state (a certificate 14 days
///   out), the refusal NPM gives a custom one, and that the refusal changes
///   neither `expires_on` nor `provider`. The "Renewal requested" arm is
///   untestable here, not unimplemented.
/// * **I-08's empty copies.** The audit log of a used lab is never empty and
///   the scenario holds one access list on purpose, so the "No access lists
///   configured." and "No audit entries reported." states are not reachable
///   from here. They belong to the screen's own widget states.
///
/// I-07 is X by design: the client has no create or delete for proxy hosts,
/// certificates or access lists, so there is no flow to drive.
void main() {
  late _Lab lab;
  NpmClient? admin;
  NpmClient? viewer;

  setUpAll(() async {
    await _scenario('apply', 'npm-lab');
    lab = _Lab.load();
    admin = NpmClient(
      url: lab.serverUrl,
      identity: lab.value('CUPOLA_TESTLAB_NPM_USERNAME'),
      secret: lab.value('CUPOLA_TESTLAB_NPM_PASSWORD'),
    );
    viewer = NpmClient(
      url: lab.serverUrl,
      identity: lab.viewerEmail,
      secret: lab.viewerPassword,
    );

    final info = await admin!.serverInfo();
    expect(info.isHealthy, isTrue, reason: 'NPM is not answering');
    expect(info.version, lab.serverVersion);
    // 2.12.3 still ships the seeded default administrator, which is the
    // credential the lab's bootstrap sets. Naming it keeps a future image bump
    // from silently changing what this file reads.
    expect(info.hasDefaultAdminRisk, isTrue);
  });

  tearDownAll(() async {
    admin?.close();
    viewer?.close();
    admin = null;
    viewer = null;
    await _scenario('teardown', 'npm-lab');
  });

  test(
    'I-04: a host is disabled and enabled, and the read-back agrees',
    () async {
      final client = admin!;
      final toggle = await _host(client, lab.toggleDomain);

      expect(toggle.enabled, isTrue, reason: 'the scenario leaves it serving');
      expect(toggle.configLoaded, isTrue);
      expect(toggle.errorText, isEmpty);
      expect(toggle.target, 'http://radarr:7878');
      expect(
        toggle.advancedConfigLines,
        greaterThan(0),
        reason: 'the scenario proves the valid block live',
      );

      final disabled = await client.setProxyHostEnabled(toggle.id, false);
      expect(disabled, isNotNull);
      expect(disabled!.enabled, isFalse);
      expect(
        disabled.configLoaded,
        isTrue,
        reason: 'a disabled host is not a fault',
      );
      expect((await _host(client, lab.toggleDomain)).enabled, isFalse);

      final enabled = await client.setProxyHostEnabled(toggle.id, true);
      expect(enabled, isNotNull);
      expect(enabled!.enabled, isTrue);
      final reread = await _host(client, lab.toggleDomain);
      expect(reread.enabled, isTrue);
      expect(reread.configLoaded, isTrue);
      expect(reread.errorText, isEmpty);
    },
  );

  test(
    'I-05: a valid block reloads, a refused one is nginx\'s own error',
    () async {
      final client = admin!;
      final host = await _host(client, lab.advancedDomain);
      expect(
        host.advancedConfig.trim(),
        isEmpty,
        reason: 'the scenario leaves this host a clean editor',
      );
      // A refusal is written further down; the host is disposable, and this
      // makes even a failed assertion leave nginx a parseable configuration.
      addTearDown(() async {
        try {
          await client.updateProxyHostAdvancedConfig(host.id, '');
        } catch (_) {
          // The scenario's teardown deletes the host anyway.
        }
      });

      final saved = await client.updateProxyHostAdvancedConfig(
        host.id,
        lab.validAdvanced,
      );
      expect(saved, isNotNull);
      expect(saved!.advancedConfig, lab.validAdvanced);
      expect(saved.advancedConfigLines, 4);
      expect(saved.configLoaded, isTrue);
      expect(saved.errorText, isEmpty);
      // The block is in nginx, not merely in the database: the extra location
      // answers with its own body instead of reaching Dockge.
      expect(
        await _served(
          lab.advancedDomain,
          '/cupola-testlab',
          expected: 'advanced-config',
        ),
        'advanced-config',
      );

      final refused = await client.updateProxyHostAdvancedConfig(
        host.id,
        lab.refusedAdvanced,
      );
      expect(refused, isNotNull);
      expect(refused!.advancedConfig, lab.refusedAdvanced);
      expect(refused.configLoaded, isFalse);
      expect(refused.hasConfigError, isTrue);
      expect(refused.errorText, contains('nginx: [emerg]'));
      expect(refused.errorText, contains('cupola_bogus_directive'));

      final restored = await client.updateProxyHostAdvancedConfig(host.id, '');
      expect(restored, isNotNull);
      expect(restored!.configLoaded, isTrue);
      expect(restored.errorText, isEmpty);
    },
  );

  test('I-06: an expiring certificate reads amber, and the refusal to renew '
      'changes nothing', () async {
    final client = admin!;
    final certificates = await client.certificates();
    final certificate = certificates.firstWhere(
      (item) => item.niceName == lab.certificateName,
      orElse: () => fail('the scenario\'s certificate is missing'),
    );
    final now = DateTime.now();

    expect(certificate.provider, 'other');
    expect(certificate.isLetsEncrypt, isFalse);
    expect(certificate.hasExpired(now), isFalse);
    expect(certificate.isExpiringSoon(now), isTrue);
    final days = certificate.daysUntilExpiry(now);
    expect(days, isNotNull);
    expect(
      days!,
      inInclusiveRange(7, 21),
      reason: 'the lab makes it 14 days out so the amber state is real',
    );
    expect(
      certificate.renewalNotCompleting(now),
      isFalse,
      reason:
          'nothing renews an uploaded certificate, so no renewal is failing',
    );

    // Declared, not skipped: an ACME-backed certificate needs an endpoint
    // and a domain the lab does not have, so there is no success arm here.
    expect(
      certificates.where((item) => item.isLetsEncrypt),
      isEmpty,
      reason:
          'the lab has no Let\'s Encrypt certificate; renewing one needs ACME',
    );

    final error = await _caught(() => client.renewCertificate(certificate.id));
    expect(error, isA<NpmException>());
    expect(
      (error! as NpmException).forbidden,
      isFalse,
      reason: 'NPM refuses the request, not the administrator',
    );

    final after = (await client.certificates()).firstWhere(
      (item) => item.id == certificate.id,
    );
    expect(after.expiresOn, certificate.expiresOn);
    expect(after.provider, certificate.provider);
    expect(after.domainNames, certificate.domainNames);
  });

  test('I-08: access lists and the audit log are the server\'s own', () async {
    final client = admin!;
    final lists = await client.accessLists();
    final list = lists.firstWhere(
      (item) => item.name == lab.accessListName,
      orElse: () => fail('the scenario\'s access list is missing'),
    );

    expect(list.satisfyAny, isFalse);
    expect(list.passAuth, isFalse);
    expect(
      list.clients.map((client) => '${client.directive} ${client.address}'),
      <String>['allow 192.168.0.0/16', 'deny all'],
    );
    expect(list.proxyHostCount, isNotNull);
    expect(list.proxyHostCount!, greaterThanOrEqualTo(1));

    final host = await _host(client, lab.advancedDomain);
    expect(host.accessListId, list.id);

    final audit = await client.auditLog();
    expect(audit, isNotEmpty);
    final domains = {lab.toggleDomain, lab.advancedDomain};
    final ours = audit
        .where(
          (entry) =>
              entry.objectType == 'proxy-host' &&
              domains.contains(entry.summary),
        )
        .toList(growable: false);
    expect(
      ours,
      isNotEmpty,
      reason: 'the scenario writes both hosts and NPM logs every write',
    );
    expect(ours.first.createdOn, isNotNull);
    expect(ours.first.action, isNotEmpty);
  });

  test(
    'a view-only account reads the box and NPM refuses every write',
    () async {
      final read = viewer!;
      final write = admin!;

      final account = await read.currentUser();
      expect(account.isAdmin, isFalse);
      expect(account.isViewOnly, isTrue);
      for (final resource in NpmResource.values) {
        expect(
          account.canManage(resource),
          isFalse,
          reason: 'the account manages ${resource.key}',
        );
      }

      final hosts = await read.proxyHosts();
      final seen = hosts.expand((host) => host.domainNames).toSet();
      expect(seen, containsAll(<String>[lab.toggleDomain, lab.advancedDomain]));
      expect(
        (await read.certificates()).where(
          (item) => item.niceName == lab.certificateName,
        ),
        isNotEmpty,
      );
      expect(
        (await read.accessLists()).where(
          (item) => item.name == lab.accessListName,
        ),
        isNotEmpty,
      );

      final toggle = hosts.firstWhere(
        (host) => host.domainNames.contains(lab.toggleDomain),
      );
      final disable = await _caught(
        () => read.setProxyHostEnabled(toggle.id, false),
      );
      expect(disable, isA<NpmException>());
      expect((disable! as NpmException).forbidden, isTrue);
      expect(
        (disable as NpmException).reason,
        ServiceFailureReason.unauthorized,
      );

      final advanced = await _caught(
        () => read.updateProxyHostAdvancedConfig(toggle.id, 'keep { }'),
      );
      expect(advanced, isA<NpmException>());
      expect((advanced! as NpmException).forbidden, isTrue);

      final certificateId = lab.certificateId;
      final renew = await _caught(() => read.renewCertificate(certificateId));
      expect(renew, isA<NpmException>());
      expect((renew! as NpmException).forbidden, isTrue);

      // NPM keeps its audit log to administrators even from a read-only
      // account; the app shows that refusal rather than an empty list.
      final audit = await _caught(() => read.auditLog());
      expect(audit, isA<NpmException>());
      expect((audit! as NpmException).forbidden, isTrue);

      final untouched = await _host(write, lab.toggleDomain);
      expect(
        untouched.enabled,
        isTrue,
        reason: 'a refused write disabled the host',
      );
      expect(untouched.advancedConfig, lab.validAdvanced);
    },
  );
}

Future<NpmProxyHost> _host(NpmClient client, String domain) async {
  final hosts = await client.proxyHosts();
  return hosts.firstWhere(
    (host) => host.domainNames.contains(domain),
    orElse: () => fail('NPM lists no proxy host for $domain'),
  );
}

/// Reads a body from NPM's HTTP port, addressed by `Host`, waiting out the
/// moment nginx takes to hand new connections to a reloaded configuration.
Future<String> _served(
  String domain,
  String path, {
  String? expected,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  String last = 'no answer';
  while (DateTime.now().isBefore(deadline)) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:8088$path'),
      );
      request.headers.set('Host', domain);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        final trimmed = body.trim();
        // The old config can still answer 200 for a beat while nginx reloads;
        // waiting for a 200 is not waiting for this block.
        if (expected == null || trimmed == expected) return trimmed;
        last = '200 $trimmed';
      } else {
        last = '${response.statusCode} $body';
      }
    } catch (error) {
      last = '$error';
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('NPM never served $domain$path through the proxy: $last');
}

Future<Object?> _caught<T>(Future<T> Function() action) async {
  try {
    await action();
  } catch (error) {
    return error;
  }
  return null;
}

Future<void> _scenario(String action, String name) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'scenario',
    action,
    name,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail(
      'testlab.py scenario $action $name failed: '
      '${result.stderr}\n${result.stdout}',
    );
  }
}

/// The scenario's contract, read from `state/npm-lab.json` rather than guessed.
class _Lab {
  _Lab._(this._values, this._state);

  factory _Lab.load() {
    final stateDir =
        Platform.environment['CUPOLA_TESTLAB_STATE_DIR'] ??
        '.ai/scratch/zz_testlab/state';
    final stateFile = File('$stateDir/npm-lab.json');
    if (!stateFile.existsSync()) {
      fail(
        'No npm-lab state at ${stateFile.path}: run '
        '`python3 test/e2e/testlab/testlab.py scenario apply npm-lab` first.',
      );
    }
    final state = (jsonDecode(stateFile.readAsStringSync()) as Map)
        .cast<String, dynamic>();

    final named = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
    final credentialsPath = named == null || named.isEmpty
        ? '$stateDir/credentials.env'
        : named;
    final file = File(credentialsPath);
    if (!file.existsSync()) {
      fail(
        'No lab credentials at ${file.path}: run '
        'test/e2e/testlab/bootstrap.sh.',
      );
    }
    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return _Lab._(values, state);
  }

  final Map<String, String> _values;
  final Map<String, dynamic> _state;

  String value(String name) {
    final value = _values[name];
    if (value == null || value.isEmpty) {
      fail('The lab credentials have no $name: run the bootstrap again.');
    }
    return value;
  }

  Map<String, dynamic> get _toggle =>
      (_state['hosts'] as Map).cast<String, dynamic>()['toggle']
          as Map<String, dynamic>;

  Map<String, dynamic> get _advanced =>
      (_state['hosts'] as Map).cast<String, dynamic>()['advanced']
          as Map<String, dynamic>;

  Map<String, dynamic> get _certificate =>
      (_state['certificate'] as Map).cast<String, dynamic>();

  Map<String, dynamic> get _accessList =>
      (_state['accessList'] as Map).cast<String, dynamic>();

  Map<String, dynamic> get _viewer =>
      (_state['viewer'] as Map).cast<String, dynamic>();

  Map<String, dynamic> get _advancedBlocks =>
      (_state['advanced'] as Map).cast<String, dynamic>();

  String get serverUrl => '${(_state['server'] as Map)['url']}';
  String get serverVersion => '${(_state['server'] as Map)['version']}';

  String get toggleDomain => '${_toggle['domain']}';
  String get advancedDomain => '${_advanced['domain']}';

  String get accessListName => '${_accessList['name']}';
  String get certificateName => '${_certificate['niceName'] ?? ''}';
  int get certificateId => (_certificate['id'] as num).toInt();

  String get viewerEmail => '${_viewer['email']}';
  String get viewerPassword => '${_viewer['password']}';

  String get validAdvanced => '${_advancedBlocks['valid']}';
  String get refusedAdvanced => '${_advancedBlocks['refused']}';
}
