import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

extension SilenceWatch on WidgetRef {
  /// When the connection of [service] this page reads first stopped
  /// answering, or null when nothing recorded it.
  ///
  /// The instant, for a line that says a time of day (`since 20:41`); the
  /// span a band prints is [watchSilence]. Not live: an instant does not move
  /// with the minutes, so nothing here watches a timer.
  ///
  /// [instanceId] is the connection a link named, else the lens, resolved by
  /// the same [effectiveInstanceId] the probe's provider was keyed by.
  DateTime? silentSince(ServiceKey service, {String? instanceId}) => read(
    silenceClockProvider,
  ).since(silenceKey(service, effectiveInstanceId(this, service, instanceId)));

  /// How long the connection of [service] this page reads has not answered, as
  /// the page draws it, or null when it should say nothing of it.
  ///
  /// [silent] is the page's own fact: it is drawing a connection that did not
  /// answer (a failed probe that [failureDidNotAnswer], a band over a read
  /// that did not come back). Anywhere else the answer is null, so a healthy
  /// page costs nothing and watches nothing here, and a fault, which is an
  /// answer, never carries a span.
  ///
  /// Also null when no silence is recorded for the connection: a cold start
  /// into a silent service has a silence only from its first probe of the run,
  /// and a band never claims a span nobody measured. Under a minute the band
  /// drops the number as well (`formatElapsedSpan`).
  ///
  /// The page rebuilds once a minute through [minuteNowProvider] while it is
  /// the page on screen, so the figure moves with the minutes; behind another
  /// tab or a pushed page it does not, and reads the time afresh when it comes
  /// back, which rebuilds it anyway.
  ///
  /// Must be called from `build`, for the dependencies it registers.
  Duration? watchSilence(
    BuildContext context,
    ServiceKey service, {
    required bool silent,
    String? instanceId,
  }) {
    if (!silent) return null;
    final since = silentSince(service, instanceId: instanceId);
    if (since == null) return null;
    final now = watchPageActivity(context, this).isLive
        ? watch(minuteNowProvider)
        : read(readClockProvider).now();
    final span = now.difference(since);
    // A silence stamped after the page's reading of the time (the two were
    // taken a frame apart) is not a negative span.
    return span.isNegative ? Duration.zero : span;
  }
}
