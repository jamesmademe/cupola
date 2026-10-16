import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/outside/data/outside_run.dart';
import 'package:cupola/features/outside/data/outside_native.dart';
import 'package:cupola/features/outside/data/outside_shelf.dart';
import 'package:cupola/features/outside/data/outside_settings.dart';

/// How long the app's run waits for its reads: they are the screen's, loaded
/// already, and the app has seconds once it leaves the screen.
const outsideAppReadBudget = Duration(seconds: 6);

/// How long after a start the app writes the widgets: long enough for the
/// Home's first answers, which the run then reads from what is loaded.
const outsideAfterStart = Duration(seconds: 8);

/// Keeps what the widgets draw as fresh as the last look at the app: once
/// [outsideAfterStart] after a start, and each time the app leaves the
/// screen, with what the person last saw. On iOS, where the system decides
/// when a background refresh runs, this is how a widget is fresh at all.
///
/// The app's run records what it shows as seen and says nothing
/// (`speak: false`): a notification of what the Home just showed is no news.
/// Its reads are the ones the screen already made, so it asks the servers
/// for little, and the route is the app's own (no probe: the app keeps it).
///
/// Phones only: a desktop has no widget, and its notifications are T3's
/// background run's, which a desktop does not have either.
final outsideKeeperProvider = Provider.autoDispose<void>((ref) {
  if (!(Platform.isIOS || Platform.isAndroid)) return;
  final container = ref.container;
  var running = false;
  Future<void> run() async {
    if (running) return;
    running = true;
    try {
      await OutsideRun(
        shelf: OutsideShelf(await outsideFolder()),
        widgets: const ChannelOutsideWidgets(),
      ).run(
        container,
        speak: false,
        enabled: container.read(outsideNoticeKindsProvider),
        probe: false,
        budget: outsideAppReadBudget,
      );
    } catch (_) {
      // The widgets keep the frames they had, which say their age.
    } finally {
      running = false;
    }
  }

  final start = Timer(outsideAfterStart, () => unawaited(run()));
  final listener = AppLifecycleListener(onHide: () => unawaited(run()));
  ref.onDispose(() {
    start.cancel();
    listener.dispose();
  });
});
