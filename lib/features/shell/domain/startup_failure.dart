import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'package:cupola/features/settings/data/settings_service.dart'
    show SecureStorageUnavailable;
import 'package:cupola/features/settings/domain/unread_secret.dart'
    show secureStoreName;

/// Where a start had got to: the settings file first, then the connections
/// kept in the platform's secure storage.
enum StartupStep {
  /// `SharedPreferences`: the region, the layout, which connections exist.
  preferences,

  /// The keys, passwords and sessions, read from the Keychain (or the
  /// platform's equivalent), and the plaintext ones of an older version
  /// moved into it.
  connections,

  /// Emptying secure storage, asked for from the page of a [connections]
  /// failure ([StartupFailure.canForget]).
  forgettingKeys,
}

/// A start that stopped before the app could be drawn, in the words the
/// failure page says.
///
/// Before this, `main` awaited its reads with nothing around them: a read that
/// threw, or never answered, left the window it had already shown black for
/// good (on a phone, the launch screen). The cause is said once, from the step
/// the start had reached, and the platform's own words wait behind Why?.
@immutable
class StartupFailure {
  const StartupFailure({
    required this.step,
    required this.error,
    this.platform,
  });

  /// The step that did not finish.
  final StartupStep step;

  /// What it threw: a [TimeoutException] when it never answered.
  final Object error;

  /// Whose secure storage is named; [defaultTargetPlatform] when null, so a
  /// test can read every platform's words.
  final TargetPlatform? platform;

  bool get timedOut => error is TimeoutException;

  /// What failed, naming what the person has lost sight of, not the API.
  String get headline => switch (step) {
    StartupStep.preferences => 'Cupola could not open its settings',
    StartupStep.connections => 'Cupola could not read your saved connections',
    StartupStep.forgettingKeys => 'Cupola could not forget the saved keys',
  };

  /// Whether forgetting the saved keys is a way on: secure storage refused
  /// the reads, and asking again may never help (a key store lost to a system
  /// update). Not for a store that never answered, which would not answer
  /// that either.
  bool get canForget =>
      step == StartupStep.connections && !timedOut && _fromSecureStorage;

  /// Why, when the step says it: the store that did not hand them over, and
  /// the one cause a person can see to (a locked keyring on Linux). Null when
  /// the error came from somewhere the step does not explain; Why? carries it.
  String? get sentence {
    if (step == StartupStep.preferences) {
      return timedOut ? "The app's settings file hasn't opened." : null;
    }
    if (step == StartupStep.forgettingKeys) {
      return (platform ?? defaultTargetPlatform) == TargetPlatform.linux
          ? "The system keyring isn't answering. Start GNOME Keyring or "
                'KWallet, then retry.'
          : '${secureStoreName(platform)} refused that too.';
    }
    if (!timedOut && !_fromSecureStorage) return null;
    final store = secureStoreName(platform);
    final verb = timedOut ? "hasn't answered" : "didn't hand them over";
    final locked = (platform ?? defaultTargetPlatform) == TargetPlatform.linux
        ? ' It may still be locked.'
        : '';
    return '$store $verb.$locked';
  }

  /// The platform's own words, behind Why?: a code and a message, never the
  /// details map, which can name a stored key. Null when there is nothing to
  /// add (a timeout says all it knows in [sentence]).
  /// Whether [error] is secure storage's: a platform refusal, or every read
  /// of the load refused ([SecureStorageUnavailable]).
  bool get _fromSecureStorage =>
      error is PlatformException || error is SecureStorageUnavailable;

  String? get why {
    var error = this.error;
    if (error is SecureStorageUnavailable) error = error.cause;
    if (error is TimeoutException) return null;
    if (error is PlatformException) {
      final message = error.message?.trim();
      return message == null || message.isEmpty
          ? 'Error ${error.code}.'
          : '$message (${error.code})';
    }
    final text = error.toString().trim();
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }
}

/// How long a start may take before it is a failure: long enough for a cold
/// Keychain on a busy machine, short enough that nobody is left looking at a
/// launch screen wondering.
const startupLimit = Duration(seconds: 20);

/// The outcome of [attemptStartup].
sealed class StartupOutcome<T> {
  const StartupOutcome();
}

final class StartupReady<T> extends StartupOutcome<T> {
  const StartupReady(this.value);
  final T value;
}

final class StartupFailed<T> extends StartupOutcome<T> {
  const StartupFailed(this.failure);
  final StartupFailure failure;
}

/// Runs [boot], which calls `reach` as it enters each step, and turns what it
/// throws, or its never finishing within [limit], into a [StartupFailure] for
/// the step it had reached.
///
/// A boot that is still running when the limit passes is left to finish on
/// its own: a platform read cannot be cancelled, and its result is dropped.
Future<StartupOutcome<T>> attemptStartup<T>(
  Future<T> Function(void Function(StartupStep step) reach) boot, {
  Duration limit = startupLimit,
}) async {
  var step = StartupStep.preferences;
  try {
    final value = await boot((reached) => step = reached).timeout(limit);
    return StartupReady(value);
  } catch (error) {
    return StartupFailed(StartupFailure(step: step, error: error));
  }
}
