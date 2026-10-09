/// The stuck downloads acted on in Needs you: each says what happened in
/// place of its card, until Activity is read again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/activity/domain/stuck_download_fault.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;

/// A way out taken on [item], and the note its card says now: `Dropped ·
/// Radarr is looking for another download`. [action] tells the card whether
/// the note carries an Undo (Keep waiting does).
typedef ActedFault = ({ServiceQueueItem item, StuckAction action, String note});

/// The acted-on downloads, by their `keptWaitingKey`.
///
/// Without it a dropped download vanished as the queue was read again, and
/// nothing said where it went. Emptied when Activity is read again (pull,
/// return, the tab tapped twice): by then the cards still there are the
/// downloads still stuck.
class ActedFaults extends Notifier<Map<String, ActedFault>> {
  @override
  Map<String, ActedFault> build() => const {};

  /// Records that [action] was taken on [item], whose card says [note].
  void act(
    String key, {
    required ServiceQueueItem item,
    required StuckAction action,
    required String note,
  }) {
    state = {...state, key: (item: item, action: action, note: note)};
  }

  /// Forgets [key]: its card is drawn again, as after an Undo.
  void forget(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }

  void clear() {
    if (state.isNotEmpty) state = const {};
  }
}

final actedFaultsProvider =
    NotifierProvider<ActedFaults, Map<String, ActedFault>>(ActedFaults.new);
