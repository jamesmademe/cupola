import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The connection well every TrueNAS section reads its failures through.
///
/// Until this existed, no screen under `features/truenas/presentation/` used
/// [AsyncValueWidget], [NotConfiguredPlaceholder] or [ServiceOfflineState] —
/// twenty-three call sites hand-rolled `.when(error: AppErrorState)` instead.
/// That is not a styling difference. `truenasClientProvider` throws
/// `TrueNasException('TrueNAS not configured')` *before* it opens a socket, so
/// a NAS nobody had set up rendered as a generic red failure card with a Retry
/// button that could never succeed — retrying a form that has not been filled
/// in. Every other service in the app answered the same condition with an
/// invitation to Settings.
///
/// Nineteen of those call sites read a provider that can be the first to
/// discover the connection is gone, and come through here. The four that do not
/// (a dataset's snapshots, an instance's devices, the two interface lists) sit
/// *inside* a body this widget already resolved, so their sibling provider
/// cannot reach a state the parent did not.
///
/// Three outcomes, in the order they are tested:
///
///  * **not configured** → [NotConfiguredPlaceholder.forService], which
///    deep-links to TrueNAS's own settings page rather than the Settings root.
///    [AsyncValueWidget] reaches the same state by string-matching the throw,
///    but only in its generic form, which lands the user on `/settings` and
///    leaves them to find the service.
///  * **the host did not answer** ([ServiceFailureReason.unreachable],
///    [ServiceFailureReason.timeout], [ServiceFailureReason.tls],
///    [ServiceFailureReason.localNetworkBlocked]) → [ServiceOfflineState]. Red
///    belongs to a connection that did not answer and to nothing else, and this
///    is the only branch that has earned it.
///  * anything else — a rejected API key, a method this SCALE build does not
///    have, a malformed payload — is a real error with a retry that can work,
///    so it goes to [AsyncValueWidget] and its [AppErrorState].
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

  /// A panel *within* a section body — the snapshot list under a dataset, the
  /// five task families on Data protection — which already sits inside a scroll
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
    } else if (failure == _TrueNasWell.offline) {
      well = ServiceOfflineState(
        serviceName: ServiceKey.truenas.title,
        accent: ServiceKey.truenas.accent,
        onRetry: onRetry,
      );
    } else {
      well = AsyncValueWidget<T>(
        value: value,
        serviceName: ServiceKey.truenas.title,
        onRetry: onRetry,
        loadingLabel: loadingLabel,
        skeleton: skeleton ?? _defaultSkeleton,
        data: data,
      );
    }

    if (_inline) return well;
    // The refresh gesture only fires over a scrollable, and the two state wells
    // are centred columns. That is deliberate: both of them carry their own
    // button (Settings, Retry), and a pull on a page that says "not set up"
    // would re-run a query that cannot answer.
    return RefreshIndicator(onRefresh: () async => onRetry(), child: well);
  }

  Widget get _defaultSkeleton => _inline
      ? AppSkeleton.listRows(count: 2)
      : ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [AppSkeleton.listRows()],
        );

  static _TrueNasWell? _connectionFailure(Object error) {
    // The same string `AsyncValueWidget` matches on, tested here first so the
    // placeholder can name the service instead of pointing at Settings at large.
    if (error.toString().contains('not configured')) {
      return _TrueNasWell.notConfigured;
    }
    if (error is! HasFailureReason) return null;
    return switch (error.reason) {
      ServiceFailureReason.unreachable ||
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

enum _TrueNasWell { notConfigured, offline }
