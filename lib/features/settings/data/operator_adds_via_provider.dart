import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// How the operator adds a title nobody holds, kept on this device across
/// launches. Through Seerr at first.
final operatorAddsViaProvider =
    NotifierProvider<OperatorAddsViaNotifier, OperatorAddsVia>(
      OperatorAddsViaNotifier.new,
    );

class OperatorAddsViaNotifier extends Notifier<OperatorAddsVia> {
  static const _key = 'operator_adds_via';

  @override
  OperatorAddsVia build() {
    // Guarded like the other preferences: a test or a screen built without
    // the preferences still draws, with the default choice.
    try {
      final stored = ref.watch(sharedPreferencesProvider).getString(_key);
      return OperatorAddsVia.values.asNameMap()[stored] ??
          OperatorAddsVia.seerr;
    } catch (_) {
      return OperatorAddsVia.seerr;
    }
  }

  void set(OperatorAddsVia value) {
    state = value;
    try {
      ref.read(sharedPreferencesProvider).setString(_key, value.name);
    } catch (_) {
      // Kept for this launch only: nothing to persist to.
    }
  }
}
