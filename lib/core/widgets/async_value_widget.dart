import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';

/// A widget that handles AsyncValue states with premium, consistent styling.
///
/// Shows loading, error, empty, or data states based on the [AsyncValue].
/// - loading  → [skeleton] (or a centred spinner if none given)
/// - error, with a retained previous value → the data it had, at full ink,
///              under a [FaultBand.unreachable] (see below) — also while the
///              provider is reloading or retrying over that error
/// - error    → [AppErrorState] with a retry button when [onRetry] is set
///              (the "not configured" case still routes to [NotConfiguredPlaceholder])
/// - data     → [emptyBuilder]/[AppEmptyState] when [isEmpty] returns true,
///              otherwise [data]
///
/// ## Why the error branch consults `hasValue` first
///
/// This widget used to call `value.when(...)`, which is the one shape of the
/// Riverpod API that cannot see a retained value: an `AsyncError` that Riverpod
/// is still carrying the previous data on routed straight to a red leaf, and
/// the readout the user opened the app to look at was discarded **at the widget
/// boundary**, after the state layer had gone to the trouble of keeping it.
///
/// A self-hosted box that stops answering is a daily condition, and the last
/// thing it said before it went quiet is the most useful thing on the screen —
/// a pool that was already degraded, a queue that was already stuck. So an
/// error over retained data draws that data, unchanged and undimmed, with a
/// band above it saying what happened. Nothing is dimmed for being
/// unreachable: dimming means *not configured* everywhere else on this canvas,
/// and the two states need opposite responses.
///
/// The full-page [AppErrorState] survives for the case it is actually for —
/// the cold open, where the service has never answered in this session and
/// there is no readout behind the band to keep.
///
/// ## Why a reload over a failure does not draw the loading state
///
/// Moving off the plain `when` was half the fix. While Riverpod retries a
/// failed build it holds `AsyncLoading(value: last, error: why)`, and `when`
/// reads every `AsyncLoading` that already had a state as a dependency reload
/// and calls `loading()` (`skipLoadingOnReload` is false by default). So for
/// the whole retry sequence the retained readout was thrown away for a
/// spinner, and under a poll it never came back: each tick invalidates, the
/// provider's disposal cancels the pending retry timer, and the retry count
/// never reaches the end that would settle into `AsyncError`. A Prowlarr or a
/// TrueNAS that went down mid-session stayed a spinner for as long as the page
/// was open, and the branch below was unreachable.
///
/// Whenever there is a value *and* an error, then, the reload's loading state
/// is skipped and the error branch draws the readout under its band. The
/// cold open keeps the spinner through a retry: with nothing retained, the
/// loading state is the honest one while a blip heals itself, which is what
/// Riverpod's default retry is left on for.
class AsyncValueWidget<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final String serviceName;

  /// Optional custom loading widget. Defaults to centered CircularProgressIndicator.
  final Widget? loadingWidget;

  /// Optional skeleton shown while loading (takes precedence over [loadingWidget]).
  final Widget? skeleton;

  /// Called to retry after an error (wired to `ref.invalidate(...)`).
  final VoidCallback? onRetry;

  /// Optional predicate identifying an "empty" data result.
  final bool Function(T data)? isEmpty;

  /// Optional widget shown when [isEmpty] returns true.
  final Widget? emptyBuilder;

  /// What a screen reader hears while [value] is loading.
  ///
  /// A shimmer skeleton is a set of bare `Container`s and a bare spinner has no
  /// text either, so both publish an empty semantics tree: a screen reader lands
  /// on a page with nothing to read and no way to tell "loading" from "empty".
  /// Defaults to `'Loading <serviceName>'`.
  final String? loadingLabel;

  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    required this.serviceName,
    this.loadingWidget,
    this.skeleton,
    this.onRetry,
    this.isEmpty,
    this.emptyBuilder,
    this.loadingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      // A refresh (an invalidate, a poll tick) already skips its loading state
      // by default; this extends the same to a reload or a retry, but only over
      // a failure that has a retained readout to show. See the class doc.
      skipLoadingOnReload: value.hasValue && value.hasError,
      data: (value) {
        if (isEmpty != null && isEmpty!(value) && emptyBuilder != null) {
          return emptyBuilder!;
        }
        return data(value);
      },
      loading: () => Semantics(
        container: true,
        // The placeholder is decoration: its shimmer boxes carry no text, and
        // its ListView/GridView would otherwise publish a scroll container over
        // content that does not exist yet.
        //
        // No `liveRegion`: this widget rebuilds on every provider tick, so a
        // polling dashboard would announce "Loading Radarr" on a loop.
        excludeSemantics: true,
        label: loadingLabel ?? 'Loading $serviceName',
        child:
            skeleton ??
            loadingWidget ??
            const Center(child: CircularProgressIndicator()),
      ),
      error: (e, stack) {
        if (e.toString().contains('not configured')) {
          return NotConfiguredPlaceholder(serviceName: serviceName);
        }

        // The retained readout, if Riverpod kept one. `hasValue` is true on an
        // `AsyncError` that carries a previous value, which is exactly the "it
        // was answering a minute ago" case. Read through `hasValue` rather than
        // a null check on the value itself, because `T` may legitimately be
        // nullable and a retained `null` is still a retained answer.
        if (value.hasValue &&
            (isEmpty == null || !isEmpty!(value.requireValue))) {
          final lastKnown = value.requireValue;
          // Classified before painted: red "did not answer" only when nothing
          // did. A refusal or a fault over retained data is amber.
          final reason = classifyConnectionFailure(e);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failureDidNotAnswer(reason))
                FaultBand.unreachable(
                  serviceName: serviceName,
                  // No `since`: nothing in the tree records a first-failure
                  // time yet, and the band drops the span rather than
                  // inventing one. When that notifier lands this is where it
                  // is plumbed in.
                  onRetry: onRetry ?? () {},
                )
              else
                FaultBand.fault(
                  serviceName: serviceName,
                  reason: reason,
                  onRetry: onRetry ?? () {},
                ),
              // Full ink, unchanged. This is the whole point of the branch.
              Flexible(child: data(lastKnown)),
            ],
          );
        }

        // The same name the loading and not-configured states use, so a region
        // says which service it is talking about in every state.
        return AppErrorState(
          error: e,
          onRetry: onRetry,
          serviceName: serviceName,
        );
      },
    );
  }
}
