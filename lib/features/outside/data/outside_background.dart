/// The run with the app off the screen: when it is asked for, and what it
/// does when the system starts it.
///
/// Android vero, iOS onesto (P-notify-honest): on Android, WorkManager runs it
/// every fifteen minutes while the phone has a network, later when the phone
/// sleeps; on iOS, a BGAppRefreshTask runs it when the system decides, which
/// can be hours apart and is never if the person closed the app by hand. Its
/// words in Settings say exactly that, and the widgets say their age.
///
/// It is asked for only while it has someone to serve: a notification switch
/// on, or a widget on a screen. With neither, nothing runs, and the person's
/// servers are not asked anything every quarter of an hour for nobody.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'package:cupola/core/startup/startup_overrides.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/outside/data/outside_native.dart';
import 'package:cupola/features/outside/data/outside_settings.dart';
import 'package:cupola/features/outside/data/outside_run.dart';
import 'package:cupola/features/outside/data/outside_shelf.dart';
import 'package:cupola/features/outside/data/outside_speaker.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart'
    show appInForegroundProvider;

/// The task's name: WorkManager's unique name, and on iOS the BGTaskScheduler
/// identifier, which `Info.plist` (`BGTaskSchedulerPermittedIdentifiers`) and
/// `AppDelegate.swift` name too.
const outsideTaskName = 'com.matthwlabs.cupola.outside';

/// How often Android runs it, at most: WorkManager's floor.
const outsideEvery = Duration(minutes: 15);

/// What the system starts: a background isolate with the app's plugins and
/// none of its screen.
@pragma('vm:entry-point')
void outsideBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == outsideTaskName) await runOutsideInBackground();
    // Always done: a run that could not read is not one to try again at once,
    // the next one comes on its own.
    return true;
  });
}

/// One run with nothing on the screen: a container built from the same start
/// as the app's, without Riverpod's retries (a read that failed is a read
/// that did not answer), over a person who has finished the way in.
Future<void> runOutsideInBackground() async {
  ProviderContainer? container;
  try {
    container = ProviderContainer(
      overrides: await readHeadlessStartup(),
      retry: (_, _) => null,
    );
    if (!container.read(onboardingCompletedProvider)) return;
    await OutsideRun(
      shelf: OutsideShelf(await outsideFolder()),
      speaker: LocalOutsideSpeaker(),
      widgets: const ChannelOutsideWidgets(),
    ).run(
      container,
      speak: true,
      enabled: container.read(outsideNoticeKindsProvider),
    );
  } catch (_) {
    // A keychain still locked after a restart, a store that cannot be read:
    // the widgets keep the frames they had, which say their age.
  } finally {
    container?.dispose();
  }
}

/// Asks the system for the background run, or stops asking.
abstract interface class OutsideScheduler {
  Future<void> ask();
  Future<void> stop();
}

class WorkmanagerOutsideScheduler implements OutsideScheduler {
  WorkmanagerOutsideScheduler();

  Future<void>? _initialized;

  Future<void> _ready() =>
      _initialized ??= Workmanager().initialize(outsideBackgroundDispatcher);

  @override
  Future<void> ask() async {
    await _ready();
    await Workmanager().registerPeriodicTask(
      outsideTaskName,
      outsideTaskName,
      frequency: outsideEvery,
      // iOS takes the first run's earliest moment from here, and every later
      // one from `AppDelegate.swift`.
      initialDelay: outsideEvery,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  @override
  Future<void> stop() async {
    await _ready();
    await Workmanager().cancelByUniqueName(outsideTaskName);
  }
}

/// The phone's scheduler; none on a desktop, which has no widget and no
/// background run.
final outsideSchedulerProvider = Provider<OutsideScheduler?>(
  (ref) => Platform.isIOS || Platform.isAndroid
      ? WorkmanagerOutsideScheduler()
      : null,
);

/// Whether one of Cupola's widgets is on a screen, asked again each time the
/// app comes back, since a widget is added with the app away.
final outsideWidgetsInstalledProvider = FutureProvider<bool>((ref) {
  ref.watch(appInForegroundProvider);
  return const ChannelOutsideWidgets().installed();
});

/// Keeps the background run asked for exactly while it serves someone: a
/// notification switch on, or a widget on a screen.
final outsideScheduleProvider = Provider<void>((ref) {
  final scheduler = ref.watch(outsideSchedulerProvider);
  if (scheduler == null) return;
  final wanted =
      ref.watch(outsideNoticeKindsProvider).isNotEmpty ||
      (ref.watch(outsideWidgetsInstalledProvider).value ?? false);
  // Nothing is said before the widgets' answer is in: an absent widget and an
  // answer not yet come are the same `false`, and stopping for that would
  // only be undone a moment later.
  if (!wanted && !ref.watch(outsideWidgetsInstalledProvider).hasValue) return;
  unawaited(
    (wanted ? scheduler.ask() : scheduler.stop()).catchError((Object _) {
      // The system's scheduler refused: the app's own runs still keep the
      // widgets as fresh as the last look.
    }),
  );
});
