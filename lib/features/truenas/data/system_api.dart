import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/alert.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/domain/models/system_info.dart';

/// System info, services, alerts, and system-configuration operations.
class TrueNasSystemApi extends TrueNasApiBase {
  const TrueNasSystemApi(super.client);

  Future<TrueNasSystemInfo> getSystemInfo() =>
      fetchObject('system.info', TrueNasSystemInfo.fromJson);

  /// The raw version string from `system.version` (e.g. `TrueNAS-SCALE-25.04.1`).
  Future<String?> getVersion() async {
    final result = await client.call('system.version');
    return stringOrNull(result);
  }

  Future<List<TrueNasServiceItem>> getServices() =>
      queryList('service.query', TrueNasServiceItem.fromJson);

  Future<void> startService(String name) =>
      client.call('service.start', [name]);

  Future<void> stopService(String name) => client.call('service.stop', [name]);

  Future<void> setServiceAutostart(int id, bool enable) =>
      client.call('service.update', [
        id,
        {'enable': enable},
      ]);

  Future<List<TrueNasAlert>> getAlerts() =>
      queryList('alert.list', TrueNasAlert.fromJson);

  Future<void> dismissAlert(String uuid) =>
      client.call('alert.dismiss', [uuid]);

  // ── System configuration ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGeneralConfig() async =>
      mapOrNull(await client.call('system.general.config')) ?? const {};

  Future<void> updateGeneralConfig(Map<String, dynamic> patch) =>
      client.call('system.general.update', [patch]);

  Future<Map<String, dynamic>> getAdvancedConfig() async =>
      mapOrNull(await client.call('system.advanced.config')) ?? const {};

  Future<void> updateAdvancedConfig(Map<String, dynamic> patch) =>
      client.call('system.advanced.update', [patch]);

  Future<List<Map<String, dynamic>>> getNtpServers() =>
      queryRawList('system.ntpserver.query');

  Future<Map<String, dynamic>> getMailConfig() async =>
      mapOrNull(await client.call('mail.config')) ?? const {};

  Future<void> updateMailConfig(Map<String, dynamic> patch) =>
      client.call('mail.update', [patch]);

  /// Sends a test email (job). [config] optionally overrides the saved config.
  Future<dynamic> sendTestMail(Map<String, dynamic>? config) =>
      client.callJob('mail.send', [
        {
          'subject': 'Cupola test email',
          'text': 'This is a test email from Cupola.',
        },
        ?config,
      ]);

  Future<List<Map<String, dynamic>>> getCertificates() =>
      queryRawList('certificate.query');

  // ── Updates ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkUpdateAvailable() async =>
      mapOrNull(await client.call('update.check_available')) ?? const {};

  Future<List<Map<String, dynamic>>> getAlertServices() =>
      queryRawList('alertservice.query');

  // ── Power ────────────────────────────────────────────────────────────────
  //
  // These two are the only calls in the app whose success is unobservable. The
  // host executes them by killing the middleware, so the WebSocket carrying the
  // request dies before any reply can come back: the future either hangs until
  // the socket's own error closes it or completes with a connection error, and
  // in both cases the outcome is indistinguishable from the call never landing.
  // Callers must not await them — see `runTrueNasDetachedAction` — and must not
  // report "done", only "shutting down".
  //
  // `reason` is required from SCALE 25.04 (this client's floor); it is what
  // lands in the host's own shutdown log, so it says which app asked rather
  // than leaving an unexplained reboot in the audit trail.

  Future<void> shutdown({String reason = 'Requested from Cupola'}) =>
      client.call('system.shutdown', [
        reason,
        {'delay': 0},
      ]);

  Future<void> reboot({String reason = 'Requested from Cupola'}) =>
      client.call('system.reboot', [
        reason,
        {'delay': 0},
      ]);
}
