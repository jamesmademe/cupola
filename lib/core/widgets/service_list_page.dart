import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/list_rows_shimmer.dart';
import 'package:cupola/core/widgets/staggered_entrance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One tab whose whole content is a flat list of records a service answered
/// with, plus the one line that says how many and in what state.
///
/// Every service tab that reads a list wants exactly this shape: the ambient
/// scaffold in the service's accent, `AsyncValueWidget` over the provider, the
/// shared empty page, a shimmer at the right row height, and pull-to-refresh
/// over a separated list. Three copies of it were written in one pass — Plex's,
/// Jellyfin's and NZBGet's — differing only in which [ServiceKey] supplied the
/// accent, which is the point at which it belongs here instead. The next tab to
/// land gets the skeleton row height, the nav-bar clearance and the stagger for
/// free, and a change to any of those is made once.
class ServiceListPage<T> extends StatelessWidget {
  /// A list with a summary line above it.
  ///
  /// The line is the list's own claim about itself — `12 devices`, `3 of 8
  /// enabled` — so it scrolls with the rows rather than floating over them.
  const ServiceListPage({
    super.key,
    required this.service,
    required this.value,
    required this.serviceName,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onRetry,
    required String Function(List<T> items) summary,
    required this.rowBuilder,
    this.header,
    this.banner,
    this.topPadding = 0,
    this.skeletonRowHeight = 72,
  }) : _summary = summary;

  /// The same page with no summary line, for a list whose rows already carry
  /// everything a count would add.
  const ServiceListPage.unsummarised({
    super.key,
    required this.service,
    required this.value,
    required this.serviceName,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onRetry,
    required this.rowBuilder,
    this.header,
    this.banner,
    this.topPadding = 0,
    this.skeletonRowHeight = 72,
  }) : _summary = null;

  /// Whose accent the page wears and whose empty state it names.
  final ServiceKey service;

  final AsyncValue<List<T>> value;

  /// Names this surface in the failure band, e.g. `Jellyfin devices`.
  final String serviceName;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  /// Re-reads the provider. Also what pull-to-refresh calls.
  final VoidCallback onRetry;

  final Widget Function(T item) rowBuilder;

  /// A control that sits above the list and outside the state ladder.
  ///
  /// Deliberately outside it: a filter is the one thing that must stay
  /// reachable when the list is **empty** or has **failed**, which is exactly
  /// when a control living in the data branch has disappeared. A tab whose
  /// filter vanishes on the empty state leaves the reader with nothing to do
  /// but go back — and the filter they need is the one that would have found
  /// records. It does not scroll away with the rows for the same reason.
  final Widget? header;

  /// A band above the rows, inside the list, in the data state only.
  ///
  /// For a claim about the records themselves — a partially fetched page, a
  /// capability the answer was missing. It scrolls with them because it
  /// qualifies them; [header] does not, because it acts on them.
  final Widget? banner;

  /// Room the floating service band and tab bar take above this page, since
  /// they hover over it rather than pushing it down.
  final double topPadding;

  final double skeletonRowHeight;

  final String Function(List<T> items)? _summary;

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final leading = (banner == null ? 0 : 1) + (summary == null ? 0 : 1);

    final page = AsyncValueWidget<List<T>>(
      value: value,
      serviceName: serviceName,
      onRetry: onRetry,
      isEmpty: (items) => items.isEmpty,
      emptyBuilder: AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          message: emptyMessage,
          accentColor: service.accent,
        ),
      ),
      skeleton: ListRowsShimmer(count: 6, rowHeight: skeletonRowHeight),
      data: (items) => RefreshIndicator(
        // `onRetry` invalidates the provider, and `AsyncValueWidget` is
        // watching it — so the rows are replaced when the answer arrives.
        // The indicator only has to stay down until the request is away.
        onRefresh: () async => onRetry(),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            // Not `AppSpacing.xxl`: the nav bar floats, so the last row
            // needs its measured height cleared or it sits underneath.
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          itemCount: items.length + leading,
          separatorBuilder: (_, index) =>
              SizedBox(height: index < leading ? AppSpacing.md : AppSpacing.sm),
          itemBuilder: (context, index) {
            var offset = index;
            if (banner != null) {
              if (offset == 0) return banner!;
              offset -= 1;
            }
            if (summary != null) {
              if (offset == 0) return _SummaryLine(label: summary(items));
              offset -= 1;
            }
            return StaggeredEntrance(
              index: offset,
              child: rowBuilder(items[offset]),
            );
          },
        ),
      ),
    );

    final coldPage = value.hasError && !value.hasValue
        ? AppScrollablePage(child: page)
        : page;

    return AmbientScaffold(
      accent: service.accent,
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: _withHeader(coldPage),
      ),
    );
  }

  Widget _withHeader(Widget child) => header == null
      ? child
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header!,
            Expanded(child: child),
          ],
        );
}

/// The list's one-line claim about itself.
///
/// Spoken as a single node: the words are the label, and the drawn `Text` is
/// silenced so a screen reader does not read the same sentence twice.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: ExcludeSemantics(
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: CupolaThemeColors.of(context).dimText,
        ),
      ),
    ),
  );
}
