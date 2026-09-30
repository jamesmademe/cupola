/// The Portal's discovery hints, and the switch behind them.
///
/// Settings → Hints carries **one row per feature that teaches itself**, not
/// one per mechanism: the demo bounce and the coach mark are two beats of a
/// single lesson — "the Portal opens with a swipe up" — so they answer to a
/// single switch, named after the feature. When another feature earns hints
/// it gets its own row and its own switch; nothing here is shared.
///
/// The contract, in one line: the × on the coach mark is that same switch.
/// Settings turns it back on — and it stays on until the × is pressed again.
/// Turning it back on also re-arms the one-shot demo, so re-enabling replays
/// the whole lesson rather than half of it. Using the Portal flips nothing:
/// it only resets the coach's need-counter, so the tip retires while the
/// habit is alive and returns on its own if the habit is lost.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

class PortalHintsState {
  const PortalHintsState({
    required this.enabled,
    required this.demoShown,
    required this.manualJourneys,
  });

  /// The single switch — Settings → Hints → Portal, and the coach mark's ×.
  final bool enabled;

  /// The one-shot demo has already played in the current enable-cycle.
  final bool demoShown;

  /// Manual service switches (dashboard → service) since the Portal was last
  /// used. Using the Portal resets it.
  final int manualJourneys;

  /// Manual journeys after which the coach mark earns its appearance.
  static const int coachJourneyThreshold = 3;

  bool get demoBouncePending => enabled && !demoShown;

  bool get coachVisible => enabled && manualJourneys >= coachJourneyThreshold;

  PortalHintsState copyWith({
    bool? enabled,
    bool? demoShown,
    int? manualJourneys,
  }) {
    return PortalHintsState(
      enabled: enabled ?? this.enabled,
      demoShown: demoShown ?? this.demoShown,
      manualJourneys: manualJourneys ?? this.manualJourneys,
    );
  }
}

final portalHintsProvider =
    NotifierProvider<PortalHintsNotifier, PortalHintsState>(
      PortalHintsNotifier.new,
    );

class PortalHintsNotifier extends Notifier<PortalHintsState> {
  static const _enabledKey = 'portal_hints_enabled';
  static const _demoShownKey = 'portal_hint_demo_shown';
  static const _journeysKey = 'portal_manual_journeys';

  @override
  PortalHintsState build() {
    // Guarded so screens still render if SharedPreferences isn't provided
    // (lightweight widget/router tests) — same contract as recent searches.
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      return PortalHintsState(
        enabled: prefs.getBool(_enabledKey) ?? true,
        demoShown: prefs.getBool(_demoShownKey) ?? false,
        manualJourneys: prefs.getInt(_journeysKey) ?? 0,
      );
    } catch (_) {
      // No persistence: report the one-shot demo as already consumed, so no
      // hint ever schedules timers under a fake clock. Real runs always have
      // SharedPreferences.
      return const PortalHintsState(
        enabled: true,
        demoShown: true,
        manualJourneys: 0,
      );
    }
  }

  /// The Settings switch, and the coach mark's × (which is `enabled: false`).
  /// Re-enabling re-arms the one-shot demo: the lesson replays whole.
  void setEnabled(bool enabled) {
    if (state.enabled == enabled) return;
    state = state.copyWith(enabled: enabled, demoShown: enabled ? false : null);
    _persist();
  }

  void markDemoShown() {
    if (state.demoShown) return;
    state = state.copyWith(demoShown: true);
    _persist();
  }

  /// A manual switch happened: `/dashboard` → a service, Portal untouched.
  void noteManualJourney() {
    state = state.copyWith(manualJourneys: state.manualJourneys + 1);
    _persist();
  }

  /// The Portal was opened for real: the coach's reason to exist resets.
  void notePortalUsed() {
    if (state.manualJourneys == 0) return;
    state = state.copyWith(manualJourneys: 0);
    _persist();
  }

  void _persist() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setBool(_enabledKey, state.enabled);
      prefs.setBool(_demoShownKey, state.demoShown);
      prefs.setInt(_journeysKey, state.manualJourneys);
    } catch (_) {
      // No persistence available (tests) — in-memory state still updates.
    }
  }
}
