import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// The notification kinds the person turned on in Settings › Notifications:
/// none until they do (P-t3-scope). Kept in the preferences, which the run
/// with the app away reads as it starts, so a switch turned off is honoured
/// by the next run without the app having to be open.
class OutsideNoticeKinds extends Notifier<Set<OutsideNoticeKind>> {
  static const key = 'outside_notices';

  @override
  Set<OutsideNoticeKind> build() {
    final names = ref.read(sharedPreferencesProvider).getStringList(key);
    return {
      for (final kind in OutsideNoticeKind.values)
        if (names?.contains(kind.name) ?? false) kind,
    };
  }

  /// Turns [kind] on or off. Asking the OS for the permission is the
  /// switch's own business (Settings › Notifications), before this.
  Future<void> set(OutsideNoticeKind kind, {required bool on}) async {
    state = {
      for (final each in OutsideNoticeKind.values)
        if (each == kind ? on : state.contains(each)) each,
    };
    await ref.read(sharedPreferencesProvider).setStringList(key, [
      for (final each in state) each.name,
    ]);
  }
}

final outsideNoticeKindsProvider =
    NotifierProvider<OutsideNoticeKinds, Set<OutsideNoticeKind>>(
      OutsideNoticeKinds.new,
    );
