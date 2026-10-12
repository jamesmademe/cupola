import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/data/virt_api.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_screen.dart';

/// A [TrueNasWsClient] that records every RPC instead of opening a socket.
class _RecordingClient extends TrueNasWsClient {
  _RecordingClient(this.responses)
    : super(baseUrl: 'https://nas.local', apiKey: 'key');

  final Map<String, dynamic> responses;
  final List<String> methods = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    methods.add(method);
    if (responses.containsKey(method)) return responses[method];
    throw TrueNasException('no stub for $method');
  }

  @override
  Future<dynamic> callJob(
    String method, [
    List<dynamic> params = const [],
    TrueNasJobProgress? onProgress,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 1),
  ]) async {
    methods.add(method);
    return responses[method];
  }
}

const _incusVm = {
  'id': 'win11',
  'name': 'win11',
  'type': 'VM',
  'status': 'RUNNING',
};
const _incusContainer = {
  'id': 'alpine',
  'name': 'alpine',
  'type': 'CONTAINER',
  'status': 'STOPPED',
};

void main() {
  group('decision 36: Incus instances only', () {
    test('the VM list asks Incus and never the legacy KVM subsystem', () async {
      // The rule, not the payload: `vm.query` is a different subsystem with
      // numeric ids and its own lifecycle RPCs, and a VM listed from it could
      // not be started by anything this section draws.
      final client = _RecordingClient({
        'virt.instance.query': [_incusVm, _incusContainer],
      });
      final api = TrueNasVirtApi(client);

      final vms = await api.getInstances('VM');

      expect(client.methods, ['virt.instance.query']);
      expect(client.methods, isNot(contains('vm.query')));
      expect(vms.map((i) => i.id), ['win11']);
    });

    test('the container list filters the same one query', () async {
      final client = _RecordingClient({
        'virt.instance.query': [_incusVm, _incusContainer],
      });

      final containers = await TrueNasVirtApi(client).getInstances('CONTAINER');

      expect(client.methods, ['virt.instance.query']);
      expect(containers.map((i) => i.id), ['alpine']);
    });

    test('a single instance is looked up in Incus alone', () async {
      final client = _RecordingClient({
        'virt.instance.query': [_incusVm],
      });

      final found = await TrueNasVirtApi(client).getInstance('win11');

      expect(found?.name, 'win11');
      expect(client.methods, ['virt.instance.query']);
    });

    test('an unknown id answers null rather than falling back', () async {
      final client = _RecordingClient({'virt.instance.query': <dynamic>[]});

      expect(await TrueNasVirtApi(client).getInstance('ghost'), isNull);
      expect(client.methods, ['virt.instance.query']);
    });

    test(
      'lifecycle goes to virt.instance.*, one door for both kinds',
      () async {
        final client = _RecordingClient({
          'virt.instance.start': null,
          'virt.instance.stop': null,
          'virt.instance.restart': null,
        });
        final api = TrueNasVirtApi(client);

        await api.start('win11');
        await api.stop('win11');
        await api.restart('win11');

        expect(client.methods, [
          'virt.instance.start',
          'virt.instance.stop',
          'virt.instance.restart',
        ]);
      },
    );
  });

  group('TrueNasVirtKind', () {
    test('the two old paths open on the pill they used to be a door for', () {
      expect(TrueNasVirtKind.fromWire('VM'), TrueNasVirtKind.vm);
      expect(TrueNasVirtKind.fromWire('vm'), TrueNasVirtKind.vm);
      expect(TrueNasVirtKind.fromWire('CONTAINER'), TrueNasVirtKind.container);
    });

    test('anything unrecognised opens on Containers, never on nothing', () {
      expect(TrueNasVirtKind.fromWire(null), TrueNasVirtKind.container);
      expect(TrueNasVirtKind.fromWire(''), TrueNasVirtKind.container);
    });

    test('the section has exactly two pills', () {
      expect(TrueNasVirtKind.values.map((k) => k.label), ['Containers', 'VMs']);
    });
  });
}
