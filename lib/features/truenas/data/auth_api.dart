import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

/// Who the session is (`auth.*`).
class TrueNasAuthApi extends TrueNasApiBase {
  const TrueNasAuthApi(super.client);

  /// The expanded roles of the key's owning user, from `auth.me`, or null
  /// when the answer carries no privilege.
  ///
  /// `auth.me` needs no role (`authorization_required=False`). An API-key
  /// session answers it from TS-25.04.0 on; 24.10 raises for a key, which the
  /// caller reads as "could not ask".
  Future<Set<String>?> myRoles() async =>
      trueNasRolesFromMe(await client.call('auth.me'));
}
