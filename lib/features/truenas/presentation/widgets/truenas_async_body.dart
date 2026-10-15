import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';

/// The connection well every TrueNAS section reads its failures through.
///
/// Until this existed, no screen under `features/truenas/presentation/` used
/// [AsyncValueWidget], [NotConfiguredPlaceholder] or [ServiceOfflineState];
/// twenty-three call sites hand-rolled `.when(error: AppErrorState)` instead.
/// That is not a styling difference. `truenasClientProvider` throws
/// `ServiceNotConfigured(ServiceKey.truenas)` *before* it opens a socket, so
/// a NAS nobody had set up rendered as a generic red failure card with a Retry
/// button that could never succeed: retrying a form that has not been filled
/// in. Every other service in the app answered the same condition with an
/// invitation to Settings.
///
/// Nineteen of those call sites read a provider that can be the first to
/// discover the connection is gone, and come through here. The four that do not
/// (a dataset's snapshots, an instance's devices, the two interface lists) sit
/// *inside* a body this widget already resolved, so their sibling provider
/// cannot reach a state the parent did not.
///
/// Four outcomes, in the order they are tested:
///
///  * **not configured** → [NotConfiguredPlaceholder.forService], which
///    deep-links to TrueNAS's own settings page rather than the Settings root.
///    [AsyncValueWidget] reaches the same state by string-matching the throw,
///    but only in its generic form, which lands the user on `/settings` and
///    leaves them to find the service.
///  * **an `http://` address** ([TrueNasInsecureTransportException]) → a well
///    that says TrueNAS needs an https:// address and offers the remedy,
///    `Change the address`, which opens its connection form. Amber: it is a
///    fault with one fix, in the form. It has no Retry, because retrying the
///    same address can only be refused again: the client never dials it.
///  * **the connection failed on the way** ([ServiceFailureReason.unreachable],
///    [ServiceFailureReason.timeout], [ServiceFailureReason.tls],
///    [ServiceFailureReason.localNetworkBlocked]) →
///    [ServiceOfflineState.failure], which says which of them it was. Red
///    belongs to a connection that did not answer and to nothing else: a
///    timeout after connecting, a certificate Cupola does not trust and a
///    blocked local network are faults, amber, the certificate with its remedy
///    (`Check the certificate`) ahead of Retry. All four used to draw the plain
///    "TrueNAS did not answer" leaf. Only with nothing retained: over a last
///    readout, [AsyncValueWidget] keeps it under its fault band.
///  * anything else: a rejected API key, a method this SCALE build does not
///    have, or a malformed payload, goes to [AsyncValueWidget] and its
///    [AppErrorState], which leads with the remedy where the form holds one
///    (`Paste the key again`) and with Retry where retrying can work.
///
/// The well lives *inside* the console pane, so the 232 rail stays visible and
/// live beside it at every width: callers put this under
/// `TrueNasConsoleShell(child: …)`, never around it.
class TrueNasAsyncBody<T> extends StatelessWidget {
  /// A section's whole body: pull-to-refresh, a list-shaped skeleton.
  const TrueNasAsyncBody({
    super.key,
    required this.value,
    required this.onRetry,
    required this.data,
    this.skeleton,
    this.loadingLabel,
  }) : _inline = false;

  /// A panel *within* a section body: the snapshot list under a dataset, the
  /// five task families on Data protection, which already sits inside a scroll
  /// view and must not nest a second [RefreshIndicator] or a full-page well.
  const TrueNasAsyncBody.inline({
    super.key,
    required this.value,
    required this.onRetry,
    required this.data,
    this.skeleton,
    this.loadingLabel,
  }) : _inline = true;

  final AsyncValue<T> value;

  /// Wired to the caller's `ref.invalidate(...)`, and reused as the
  /// pull-to-refresh gesture so both affordances mean the same thing.
  final VoidCallback onRetry;

  final Widget Function(T data) data;

  /// Defaults to the list-rows shimmer the sections were already using.
  final Widget? skeleton;

  /// What a screen reader hears while loading; defaults to "Loading TrueNAS".
  final String? loadingLabel;

  final bool _inline;

  @override
  Widget build(BuildContext context) {
    final failure = value.hasError ? _connectionFailure(value.error!) : null;
    final Widget well;
    if (failure == _TrueNasWell.notConfigured) {
      well = NotConfiguredPlaceholder.forService(ServiceKey.truenas);
    } else if (failure == _TrueNasWell.needsHttps) {
      well = const _NeedsHttps();
    } else if (failure == _TrueNasWell.offline && !value.hasValue) {
      // Only on a cold open. A NAS that answered a minute ago and then went
      // quiet still has its last readout, which is the most useful thing on
      // the screen: a pool that was already degraded stays visible under the
      // fault band [AsyncValueWidget] draws over it. This well used to win
      // over a retained value too, and the pool vanished for a "did not
      // answer" page the moment one poll failed.
      //
      // Told why, so only silence reads as silence: a certificate or a
      // timeout is a fault, amber, and the leaf names the host it was about.
      well = ServiceOfflineState.failure(
        service: ServiceKey.truenas,
        error: value.error!,
        onRetry: onRetry,
      );
    } else {
      well = AsyncValueWidget<T>(
        value: value,
        serviceName: ServiceKey.truenas.title,
        silentService: ServiceKey.truenas,
        onRetry: onRetry,
        loadingLabel: loadingLabel,
        skeleton: skeleton ?? _defaultSkeleton,
        data: data,
      );
    }

    if (_inline) return well;

    // A cold error state is a page, not a fixed-height leaf. TrueNAS keeps its
    // console shell on desktop, so the compact 720pt frame can leave only a
    // short pane below the chrome; the full not-configured copy (icon, two
    // lines and action) must be able to scroll instead of overflowing. Do not
    // wrap a retained-value error: that branch deliberately returns a bounded
    // FaultBand + live body column, and the body owns its own scroll view.
    final pageWell = value.hasError && !value.hasValue && !value.isLoading
        ? AppScrollablePage(child: well)
        : well;

    // The refresh gesture only fires over a scrollable, and the two state wells
    // are centred columns. That is deliberate: both of them carry their own
    // button (Settings, Retry), and a pull on a page that says "not set up"
    // would re-run a query that cannot answer.
    return RefreshIndicator(onRefresh: () async => onRetry(), child: pageWell);
  }

  Widget get _defaultSkeleton => _inline
      ? AppSkeleton.listRows(count: 2)
      : ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [AppSkeleton.listRows()],
        );

  static _TrueNasWell? _connectionFailure(Object error) {
    // The same type `AsyncValueWidget` matches on, tested here first so the
    // placeholder can name the service instead of pointing at Settings at large.
    if (error is ServiceNotConfigured) {
      return _TrueNasWell.notConfigured;
    }
    // Before the reason switch: it reports `notFound` only because the enum has
    // no word for it, and the generic error card would offer a Retry that the
    // client is bound to refuse.
    if (error is TrueNasInsecureTransportException) {
      return _TrueNasWell.needsHttps;
    }
    if (error is! HasFailureReason) return null;
    return switch (error.reason) {
      ServiceFailureReason.unreachable ||
      ServiceFailureReason.unreachableAtBoth ||
      ServiceFailureReason.timeout ||
      ServiceFailureReason.tls ||
      ServiceFailureReason.localNetworkBlocked => _TrueNasWell.offline,
      // A rejected key, a missing RPC or a 5xx all reached the host: the server
      // is answering, so "did not answer" would be a lie and the raw message is
      // the actionable part.
      _ => null,
    };
  }
}

enum _TrueNasWell { notConfigured, needsHttps, offline }

/// The address is `http://`, and the client refused to send the API key over
/// it (see [TrueNasInsecureTransportException]).
///
/// The one action is the fix, in the remedy's own words (`Change the
/// address`, from the same [FailureRemedy] every failure state offers): it
/// opens TrueNAS's connection form, where the address is edited and the
/// connection test offers to trust a self-signed certificate. It used to say
/// "Open Settings", which named a place rather than the thing to do there.
class _NeedsHttps extends StatelessWidget {
  const _NeedsHttps();

  static const _reason = ServiceFailureReason.insecureTransport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remedy = FailureRemedy.forReason(ServiceKey.truenas, _reason)!;
    return AppEmptyState(
      icon: Icons.no_encryption_outlined,
      // A fault the user can fix, so the tone rule's amber, never red, which
      // is kept for a host that did not answer; this one was never asked.
      accentColor: statusToneColor(colorScheme, failureTone(_reason)),
      title: failureHeadline(_reason, subject: ServiceKey.truenas.title),
      message: TrueNasInsecureTransportException.explanation,
      // The fault's one amber fill, as on every other fault's remedy.
      action: FilledButton(
        onPressed: () => remedy.open(context),
        style: remedyFillStyle(context),
        child: Text(remedy.label),
      ),
    );
  }
}
