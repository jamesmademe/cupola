import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// How long Cupola waits for a release search, and how many it runs at once.
///
/// Persisted, because both are statements about the user's own stack rather than
/// about this visit: an instance behind a slow proxy wants a different ceiling
/// every time, not once.
class ReleaseSearchSettings {
  const ReleaseSearchSettings({
    required this.concurrency,
    required this.timeout,
    this.notifyOnFinish = false,
    this.backgroundEnabled = false,
  });

  final int concurrency;
  final Duration timeout;

  /// Off until the user asks for it. Turning it on is also the only moment
  /// notification permission is requested: asking at launch, before they have
  /// expressed any interest, is exactly the pattern this avoids.
  final bool notifyOnFinish;

  /// Whether a search may be handed to the operating system to finish.
  ///
  /// **Off by default, and that is a privacy decision rather than a
  /// conservative one.** Background execution means the OS runs the request on
  /// Cupola's behalf, which it can only do by writing the request, the arr
  /// admin API key in its headers included, to system storage for the life of
  /// the task. No amount of Dart care avoids that: it is the price of the
  /// capability, not a defect of the library. So the capability is opt-in, and
  /// the trade-off is stated where the switch is.
  ///
  /// What this flag does **not** gate is the plugin's initialisation. See
  /// `configureBackgroundSearch`: the same call that would be skipped is the
  /// one that purges the records a previous session left behind, so skipping it
  /// would turn switching this off into a privacy regression.
  final bool backgroundEnabled;

  ReleaseSearchSettings copyWith({
    int? concurrency,
    Duration? timeout,
    bool? notifyOnFinish,
    bool? backgroundEnabled,
  }) {
    return ReleaseSearchSettings(
      concurrency: concurrency ?? this.concurrency,
      timeout: timeout ?? this.timeout,
      notifyOnFinish: notifyOnFinish ?? this.notifyOnFinish,
      backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
    );
  }

  /// Lowest and highest the user may set.
  ///
  /// The timeout stops at **ten** minutes rather than fifteen on purpose: the
  /// background library's own iOS ceiling is fifteen and is fixed at startup, so
  /// letting the user reach it would let the two meet, and a timeout that
  /// coincides with the transport's own gives two different failures the same
  /// elapsed, which is exactly the ambiguity the verdicts exist to remove.
  static const minConcurrency = 1;
  static const maxConcurrency = 4;
  static const minTimeout = Duration(minutes: 1);
  static const maxTimeout = Duration(minutes: 10);
}

final releaseSearchSettingsProvider =
    NotifierProvider<ReleaseSearchSettingsNotifier, ReleaseSearchSettings>(
      ReleaseSearchSettingsNotifier.new,
    );

class ReleaseSearchSettingsNotifier extends Notifier<ReleaseSearchSettings> {
  static const _concurrencyKey = 'release_search_concurrency';
  static const _timeoutKey = 'release_search_timeout_minutes';
  static const _notifyKey = 'release_search_notify';

  /// Plain preferences rather than secure storage: a feature switch is not a
  /// secret, and the same reasoning already governs the measurement stores.
  static const _backgroundEnabledKey = 'release_search_background_enabled';

  @override
  ReleaseSearchSettings build() {
    // Guarded the way every other persisted notifier here is, so a widget test
    // that never provided SharedPreferences still renders.
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      return ReleaseSearchSettings(
        concurrency: prefs.getInt(_concurrencyKey) ?? kDefaultSearchConcurrency,
        timeout: Duration(
          minutes:
              prefs.getInt(_timeoutKey) ??
              kReleaseSearchReceiveTimeout.inMinutes,
        ),
        notifyOnFinish: prefs.getBool(_notifyKey) ?? false,
        backgroundEnabled: prefs.getBool(_backgroundEnabledKey) ?? false,
      );
    } catch (_) {
      return ReleaseSearchSettings(
        concurrency: kDefaultSearchConcurrency,
        timeout: kReleaseSearchReceiveTimeout,
      );
    }
  }

  void setConcurrency(int value) {
    final clamped = value.clamp(
      ReleaseSearchSettings.minConcurrency,
      ReleaseSearchSettings.maxConcurrency,
    );
    state = state.copyWith(concurrency: clamped);
    _persistInt(_concurrencyKey, clamped);
  }

  void setTimeoutMinutes(int minutes) {
    final clamped = minutes.clamp(
      ReleaseSearchSettings.minTimeout.inMinutes,
      ReleaseSearchSettings.maxTimeout.inMinutes,
    );
    state = state.copyWith(timeout: Duration(minutes: clamped));
    _persistInt(_timeoutKey, clamped);
  }

  /// Records the user's choice. The caller asks the OS *first* and passes what
  /// it answered, so a denied permission never leaves the toggle claiming to be
  /// on.
  void setNotifyOnFinish(bool value) {
    state = state.copyWith(notifyOnFinish: value);
    _persistBool(_notifyKey, value);
  }

  /// Records the choice only. **Everything that has to happen around it:
  /// cancelling the searches already in flight, then pruning the records they
  /// leave behind, lives in [BackgroundSearchSwitch], because the order is
  /// load-bearing** and a setter nobody can see the sequence in is where that
  /// order goes to die.
  void setBackgroundEnabled(bool value) {
    state = state.copyWith(backgroundEnabled: value);
    _persistBool(_backgroundEnabledKey, value);
  }

  void _persistInt(String key, int value) {
    try {
      ref.read(sharedPreferencesProvider).setInt(key, value);
    } catch (_) {
      // Nothing to persist to; the in-memory value still applies this session.
    }
  }

  void _persistBool(String key, bool value) {
    try {
      ref.read(sharedPreferencesProvider).setBool(key, value);
    } catch (_) {
      // Nothing to persist to; the session still honours the choice.
    }
  }
}
