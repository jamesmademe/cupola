import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class SeerrIssuesScreen extends ConsumerStatefulWidget {
  const SeerrIssuesScreen({super.key, this.topPadding = _hostedTopPadding});

  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  final double topPadding;

  @override
  ConsumerState<SeerrIssuesScreen> createState() => _SeerrIssuesScreenState();
}

class _SeerrIssuesScreenState extends ConsumerState<SeerrIssuesScreen> {
  SeerrIssueFilter _filter = SeerrIssueFilter.open;

  @override
  Widget build(BuildContext context) {
    if (!ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.seerr)) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    final issues = ref.watch(seerrIssuesProvider(_filter));
    return AmbientScaffold(
      accent: ServiceKey.seerr.accent,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(seerrIssuesProvider(_filter)),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            widget.topPadding + MediaQuery.paddingOf(context).top,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            _FilterChips(
              selected: _filter,
              onSelected: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            AsyncValueWidget<SeerrAdminResult<SeerrIssue>>(
              value: issues,
              serviceName: 'Seerr issues',
              onRetry: () => ref.invalidate(seerrIssuesProvider(_filter)),
              isEmpty: (result) => result.items.isEmpty,
              emptyBuilder: AppEmptyStatePage(
                emptyState: AppEmptyState(
                  icon: Icons.report_problem_outlined,
                  title: 'No issues',
                  message: 'Seerr has no issues in this view.',
                  accentColor: ServiceKey.seerr.accent,
                ),
              ),
              data: (result) => Column(
                children: [
                  if (result.isPartial)
                    FaultBand.section(
                      message:
                          'Seerr returned ${result.items.length} of '
                          '${result.total} issues; later pages are unavailable.',
                      onRetry: () =>
                          ref.invalidate(seerrIssuesProvider(_filter)),
                    ),
                  for (final issue in result.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _IssueCard(
                        issue: issue,
                        // The record's own status, not the filter that fetched
                        // it: keyed on the filter, the "All" tab offered
                        // Resolve on nothing at all, open issues included.
                        onResolve: issue.isOpen ? () => _resolve(issue) : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(SeerrIssue issue) async {
    // A write, so the failure surfaces. Unguarded, a token that had lost
    // `MANAGE_ISSUES` threw out of the button callback: nothing invalidated,
    // nothing said, and the row still open — indistinguishable from a tap that
    // never registered.
    try {
      await ref.read(seerrServiceProvider).resolveIssue(issue.id);
      ref.invalidate(seerrIssuesProvider(_filter));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Issue resolved')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve the issue: $error')),
      );
    }
  }
}

class SeerrUsersScreen extends ConsumerWidget {
  const SeerrUsersScreen({super.key, this.topPadding = _hostedTopPadding});

  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.seerr)) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    final users = ref.watch(seerrUsersProvider);
    return AmbientScaffold(
      accent: ServiceKey.seerr.accent,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(seerrUsersProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            topPadding + MediaQuery.paddingOf(context).top,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            AsyncValueWidget<SeerrAdminResult<SeerrUser>>(
              value: users,
              serviceName: 'Seerr users',
              onRetry: () => ref.invalidate(seerrUsersProvider),
              isEmpty: (result) => result.items.isEmpty,
              emptyBuilder: AppEmptyStatePage(
                emptyState: AppEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No users',
                  message: 'Seerr returned no users.',
                  accentColor: ServiceKey.seerr.accent,
                ),
              ),
              data: (result) => Column(
                children: [
                  if (result.isPartial)
                    FaultBand.section(
                      message:
                          'Seerr returned ${result.items.length} of '
                          '${result.total} users; later pages are unavailable.',
                      onRetry: () => ref.invalidate(seerrUsersProvider),
                    ),
                  for (final user in result.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _UserCard(user: user),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final SeerrIssueFilter selected;
  final ValueChanged<SeerrIssueFilter> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final filter in SeerrIssueFilter.values)
        FilterChip(
          label: Text(filter.label),
          selected: selected == filter,
          showCheckmark: false,
          onSelected: (_) => onSelected(filter),
          selectedColor: ServiceKey.seerr.accent,
          backgroundColor: ServiceKey.seerr.accent.withValues(alpha: 0.10),
          labelStyle: Theme.of(context).textTheme.labelLarge
              ?.weight(FontWeight.w700)
              .copyWith(
                color: selected == filter
                    ? ServiceTheme.foregroundOn(ServiceKey.seerr.accent)
                    : ServiceKey.seerr.accent,
              ),
        ),
    ],
  );
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue, this.onResolve});

  final SeerrIssue issue;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = issue.media?.title ?? 'Unknown media';
    final reporter = issue.createdBy?.displayName ?? 'Unknown reporter';
    final status = issue.isResolved ? 'Resolved' : 'Open';
    return AppCard.outlined(
      semanticLabel: title,
      semanticValue: '$status, ${issue.issueTypeLabel}, reported by $reporter',
      backgroundColor: colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.report_problem_outlined,
            color: statusToneColor(
              colorScheme,
              issue.tone,
              surface: colorScheme.surfaceContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.weight(FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  joinDisplayParts([
                    issue.issueTypeLabel,
                    reporter,
                    issue.commentCount == 0
                        ? null
                        : '${issue.commentCount} comments',
                  ]),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (onResolve != null)
            IconButton(
              tooltip: 'Resolve issue',
              onPressed: onResolve,
              icon: const Icon(Icons.check_circle_outline_rounded),
            ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final SeerrUser user;

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.substring(0, 1).toUpperCase();
    return AppCard.outlined(
      semanticLabel: user.displayName,
      semanticValue: '${user.requestCount ?? '—'} requests',
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: ServiceKey.seerr.accent.withValues(alpha: 0.15),
            child: Text(initial),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.weight(FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  user.email ?? '—',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Text(
            '${user.requestCount ?? '—'} requests',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
