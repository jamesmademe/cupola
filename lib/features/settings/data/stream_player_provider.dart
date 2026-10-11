import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';

/// The app the viewer chose to play a Jellyfin title in, kept on this device.
/// Null means ask every time: nothing is preferred by default.
final streamPlayerChoiceProvider =
    NotifierProvider<StreamPlayerChoiceNotifier, StreamPlayer?>(
      StreamPlayerChoiceNotifier.new,
    );

class StreamPlayerChoiceNotifier extends Notifier<StreamPlayer?> {
  static const _key = 'stream_player';

  @override
  StreamPlayer? build() {
    // Guarded like the other preferences: a test or a screen built without
    // the preferences still draws, asking every time.
    try {
      final stored = ref.watch(sharedPreferencesProvider).getString(_key);
      return StreamPlayer.values.asNameMap()[stored];
    } catch (_) {
      return null;
    }
  }

  /// Remembers [player], or forgets the choice when it is null.
  void set(StreamPlayer? player) {
    state = player;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (player == null) {
        prefs.remove(_key);
      } else {
        prefs.setString(_key, player.name);
      }
    } catch (_) {
      // Kept for this launch only: nothing to persist to.
    }
  }
}
