import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/virt_instance.dart';

/// Incus virtualization: LXC containers and VMs (`virt.instance.*`,
/// `virt.device.*`, `virt.global.*`). Available on TrueNAS SCALE 25.04+.
class TrueNasVirtApi extends TrueNasApiBase {
  const TrueNasVirtApi(super.client);

  Future<TrueNasVirtGlobalConfig> getGlobalConfig() =>
      fetchObject('virt.global.config', TrueNasVirtGlobalConfig.fromJson);

  /// Instances of a given [type] (`CONTAINER` or `VM`).
  ///
  /// Incus only. This used to union `virt.instance.query` with `vm.query`, the
  /// legacy KVM subsystem, because a server can carry VMs from both — but the
  /// two are not interchangeable: a legacy VM has a numeric id, needs the
  /// `vm.*` RPCs for every lifecycle call, and exists whether or not Incus has
  /// a storage pool, which is why the VM door had to bypass the readiness gate
  /// to show them at all. Decision 36 drops that half: SCALE 25.04 is this
  /// client's floor, Incus is what 25.04 has, and a list nothing on this page
  /// can start is worse than a list that says why it is empty.
  Future<List<TrueNasVirtInstance>> getInstances(String type) async {
    final all = await queryList(
      'virt.instance.query',
      TrueNasVirtInstance.fromJson,
    );
    return all
        .where((i) => i.type.toUpperCase() == type.toUpperCase())
        .toList(growable: false);
  }

  Future<TrueNasVirtInstance?> getInstance(String id) async {
    final result = await client.call('virt.instance.query', [
      [
        ['id', '=', id],
      ],
    ]);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return TrueNasVirtInstance.fromJson(
        Map<String, dynamic>.from(result.first as Map),
      );
    }
    return null;
  }

  Future<List<TrueNasVirtDevice>> getDevices(String id) =>
      queryList('virt.instance.device_list', TrueNasVirtDevice.fromJson, [id]);

  Future<dynamic> start(String id) =>
      client.callJob('virt.instance.start', [id]);

  Future<dynamic> stop(String id, {bool force = false}) =>
      client.callJob('virt.instance.stop', [
        id,
        {'force': force, 'timeout': -1},
      ]);

  Future<dynamic> restart(String id, {bool force = false}) =>
      client.callJob('virt.instance.restart', [
        id,
        {'force': force, 'timeout': -1},
      ]);

  Future<dynamic> create(Map<String, dynamic> payload) =>
      client.callJob('virt.instance.create', [payload]);

  Future<dynamic> delete(String id) =>
      client.callJob('virt.instance.delete', [id]);
}
