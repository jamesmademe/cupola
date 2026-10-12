import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// A widget that handles AsyncValue states with premium, consistent styling.
///
/// Shows loading, error, empty, or data states based on the [AsyncValue].
/// - loading  → [skeleton] (or a centred spinner if none given), only while
///              there is nothing to show: a reload or a refresh over data
///              keeps the data
/// - error, with a retained previous value → the data it had, at full ink,
///              under a [FaultBand.unreachable] (see below), also while the
///              provider is reloading or retrying over that error
/// - error    → [AppErrorState] with a retry button, or, for a
///              [AsyncValueWidget.section], one [InlineErrorRetry] line
///              (the "not configured" case still routes to [NotConfiguredPlaceholder])
/// - error from a client closed under the read ([isClosedClientFailure]) →
///              not an error: the retained value, or the loading state, while
///              the provider reads again on its rebuilt client
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
/// thing it said before it went quiet is the most useful thing on the screen:
/// a pool that was already degraded, a queue that was already stuck. So an
/// error over retained data draws that data, unchanged and undimmed, with a
/// band above it saying what happened. Nothing is dimmed for being
/// unreachable: dimming means *not configured* everywhere else on this canvas,
/// and the two states need opposite responses.
///
/// The full-page [AppErrorState] survives for the case it is actually for:
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
///
/// ## Why a reload over data does not draw the loading state either
///
/// A reload is the provider building again because something it watches
/// changed: the source it derives from was read again, a setting it reads was
/// written, the lens moved. It used to skip its loading state only over a
/// failure, so over a healthy readout every one of those emptied the page to
/// a skeleton and filled it again: a pull on a list whose figures are derived
/// from it blanked the figures, for an answer that was on screen a moment
/// before. Whatever there is stays until the new answer replaces it, as it
/// does under a refresh.
/// [value] as a page under a [FaultBand] draws it: over a failure that kept
/// the last read, that read as plain data, so the rows stand at full ink under
/// the band that already says what failed, never a second failure line or a
/// skeleton. Unchanged when the page is not [banded], or kept nothing.
AsyncValue<T> lastReadUnderBand<T>(
  AsyncValue<T> value, {
  required bool banded,
}) => banded && value.hasValue ? AsyncData(value.requireValue) : value;

/// Whether [AsyncValueWidget] draws [value] as its last read under a band: a
/// failure that kept the previous answer.
///
/// For a page whose rows are built inside the widget's data builder and so
/// cannot see the branch the widget took: it asks the same question here, to
/// tell its rows they are stale (`ReadAgeWatch.watchQueueReadAge`). Mirrors the
/// error branch of [AsyncValueWidget.build], including its leaving a read whose
/// client was closed under it out of the band.
bool showsLastReadUnderBand(AsyncValue<Object?> value) =>
    value.hasError && value.hasValue && !isClosedClientFailure(value.error);

class AsyncValueWidget<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final String serviceName;

  /// Optional custom loading widget. Defaults to centered CircularProgressIndicator.
  final Widget? loadingWidget;

  /// Optional skeleton shown while loading (takes precedence over [loadingWidget]).
  final Widget? skeleton;

  /// Called to retry after an error (wired to `ref.invalidate(...)`).
  ///
  /// Required, because every failure this draws offers Retry. It used to be
  /// optional, and the band over a retained readout was handed `() {}` when it
  /// was left out: a Retry that did nothing, a control that fails in the
  /// user's hand.
  final VoidCallback onRetry;

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

  /// Whose read this is, for a [AsyncValueWidget.section]'s line and its
  /// remedy. Null on the page variant, which names the service by
  /// [serviceName] alone.
  final ServiceKey? service;

  /// What the section is without, for a [AsyncValueWidget.section]'s line:
  /// the second half of `Plex answered with an error, so <consequence>.`
  final String? consequence;

  /// The connection the read went to, when the section knows it.
  final String? instanceId;

  /// True for [AsyncValueWidget.bleedSection]: the body runs to the window
  /// edge, so the failure line keeps its own margin to reach the column.
  final bool _bleeds;

  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    required this.serviceName,
    this.loadingWidget,
    this.skeleton,
    required this.onRetry,
    this.isEmpty,
    this.emptyBuilder,
    this.loadingLabel,
  }) : service = null,
       consequence = null,
       instanceId = null,
       _bleeds = false;

  /// One region of a page whose other regions stand: a section of an
  /// Overview, under a header that already names it.
  ///
  /// A cold failure is one line in the slot the rows would fill
  /// ([InlineErrorRetry], worded by [sectionFailureMessage]), never the
  /// page-sized [AppErrorState]: a big glyph, a headline and a centred
  /// remedy inside a section read as the whole page failing, under a header
  /// that is still standing. Every other state is the page variant's.
  ///
  /// For a body already inset to the page column (`ServiceOverviewSection`):
  /// the line sits flush on it. A body that bleeds to the window edge is
  /// [AsyncValueWidget.bleedSection].
  AsyncValueWidget.section({
    super.key,
    required this.value,
    required this.data,
    required ServiceKey this.service,
    required String this.consequence,
    required this.onRetry,
    this.instanceId,
    this.skeleton,
    this.isEmpty,
    this.emptyBuilder,
    this.loadingLabel,
  }) : serviceName = service.title,
       loadingWidget = null,
       _bleeds = false;

  /// [AsyncValueWidget.section] for a body that runs to the window edge (a
  /// poster rail under `ServiceOverviewSection.bleed`): the failure line keeps
  /// its own margin, so it still starts on the page column.
  AsyncValueWidget.bleedSection({
    super.key,
    required this.value,
    required this.data,
    required ServiceKey this.service,
    required String this.consequence,
    required this.onRetry,
    this.instanceId,
    this.skeleton,
    this.isEmpty,
    this.emptyBuilder,
    this.loadingLabel,
  }) : serviceName = service.title,
       loadingWidget = null,
       _bleeds = true;

  Widget _data(T value) {
    if (isEmpty != null && isEmpty!(value) && emptyBuilder != null) {
      return emptyBuilder!;
    }
    return data(value);
  }

  Widget _loading() => Semantics(
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
  );

  @override
  Widget build(BuildContext context) {
    // A read whose client was closed under it by a settings change is not a
    // failure of the service's: the provider reads again on the rebuilt
    // client. What it had stays up meanwhile, or the loading state when it
    // had nothing; never a band or a page saying it did not answer.
    if (value.hasError && isClosedClientFailure(value.error)) {
      return value.hasValue ? _data(value.requireValue) : _loading();
    }
    return value.when(
      // A refresh (an invalidate, a poll tick) already skips its loading state
      // by default; this extends the same to a reload or a retry whenever
      // there is a readout to keep, data or a failure over data. See the
      // class doc.
      skipLoadingOnReload: value.hasValue,
      data: _data,
      loading: _loading,
      error: (e, stack) {
        if (e is ServiceNotConfigured) {
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
                  onRetry: onRetry,
                )
              else
                FaultBand.fault(
                  serviceName: serviceName,
                  reason: reason,
                  gateway: accessGatewayOf(e),
                  onRetry: onRetry,
                ),
              // Full ink, unchanged. This is the whole point of the branch.
              Flexible(child: data(lastKnown)),
            ],
          );
        }

        if (service case final section?) {
          final message = sectionFailureMessage(
            section,
            e,
            consequence: consequence!,
          );
          return _bleeds
              ? InlineErrorRetry(
                  message: message,
                  error: e,
                  service: section,
                  instanceId: instanceId,
                  onRetry: onRetry,
                )
              : InlineErrorRetry.flush(
                  message: message,
                  error: e,
                  service: section,
                  instanceId: instanceId,
                  onRetry: onRetry,
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
