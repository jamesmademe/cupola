import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/domain/kept_waiting.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The stuck downloads kept waiting, by [keptWaitingKey], kept across
/// launches: the choice is for a day, and a day outlives the app's process.
final keptWaitingProvider =
    NotifierProvider<KeptWaitingNotifier, Map<String, KeptWaiting>>(
      KeptWaitingNotifier.new,
    );

/// A download's identity across reads: its service, its connection and its
/// id there. The same row read again a minute later has the same key.
String keptWaitingKey(ServiceQueueItem item) =>
    '${item.service.routeParam}-${item.instanceId}-${item.id}';

/// Whether [item]'s stall stays out of the faults at [now].
bool isKeptWaiting(
  ServiceQueueItem item,
  Map<String, KeptWaiting> kept,
  DateTime now,
) =>
    kept[keptWaitingKey(item)]?.holds(
      currentProgress: item.progress,
      now: now,
    ) ??
    false;

class KeptWaitingNotifier extends Notifier<Map<String, KeptWaiting>> {
  static const _key = 'activity_kept_waiting';

  @override
  Map<String, KeptWaiting> build() {
    // Guarded like the other small preferences: a test or a screen built
    // without them still draws, with nothing kept.
    try {
      final raw = ref.watch(sharedPreferencesProvider).getString(_key);
      if (raw == null) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final kept = <String, KeptWaiting>{};
      for (final MapEntry(:key, :value) in decoded.entries) {
        final choice = KeptWaiting.fromJson(value);
        if (key is String && choice != null) kept[key] = choice;
      }
      return kept;
    } catch (_) {
      return const {};
    }
  }

  /// Keeps [item] waiting from [now]; returns the choice, for the note that
  /// says until when.
  KeptWaiting keep(ServiceQueueItem item, {required DateTime now}) {
    final choice = KeptWaiting.from(now: now, progress: item.progress);
    _write({
      // The lapsed ones go with the next write, so the store never grows.
      for (final MapEntry(:key, :value) in state.entries)
        if (now.isBefore(value.until)) key: value,
      keptWaitingKey(item): choice,
    });
    return choice;
  }

  /// Undo: the fault comes back at once.
  void release(ServiceQueueItem item) {
    final key = keptWaitingKey(item);
    if (!state.containsKey(key)) return;
    _write({...state}..remove(key));
  }

  void _write(Map<String, KeptWaiting> next) {
    state = next;
    try {
      ref
          .read(sharedPreferencesProvider)
          .setString(
            _key,
            jsonEncode({
              for (final MapEntry(:key, :value) in next.entries)
                key: value.toJson(),
            }),
          );
    } catch (_) {
      // Kept for this launch only: nothing to persist to.
    }
  }
}
