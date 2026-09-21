import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/presentation/background_search_switch.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/release_search/presentation/widgets/search_headroom_card.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

/// Settings for background release search — and, underneath them, the limits.
///
/// This is the third home in the awareness topology: the place a constraint that
/// shapes the user's setup lives, next to the setting it shapes. Written in the
/// second person and in the order someone actually meets these limits.
class ReleaseSearchSettingsScreen extends ConsumerStatefulWidget {
  const ReleaseSearchSettingsScreen({super.key});

  @override
  ConsumerState<ReleaseSearchSettingsScreen> createState() =>
      _ReleaseSearchSettingsScreenState();
}

class _ReleaseSearchSettingsScreenState
    extends ConsumerState<ReleaseSearchSettingsScreen> {
  bool _asking = false;

  /// Hands the flip to [BackgroundSearchSwitch], which owns the order.
  Future<void> _toggleBackground(bool wanted) =>
      ref.read(backgroundSearchSwitchProvider).set(wanted);

  /// Asks the OS **first**, then records what it answered — so a denied
  /// permission never leaves the toggle claiming to be on.
  Future<void> _toggleNotifications(bool wanted) async {
    final notifier = ref.read(releaseSearchSettingsProvider.notifier);
    if (!wanted) {
      notifier.setNotifyOnFinish(false);
      return;
    }
    setState(() => _asking = true);
    var granted = false;
    try {
      granted = await ref
          .read(releaseSearchNotificationsProvider)
          .requestPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _asking = false);
    notifier.setNotifyOnFinish(granted);
    // The OS answer just changed, so the line under the row must be re-read
    // rather than left showing what was true before the prompt.
    ref.invalidate(notificationPermissionProvider);
    if (!granted) {
      // Two different refusals, two different fixes — sending a Windows user
      // to hunt through system settings for a permission that was never asked
      // for would be a wild-goose chase.
      SnackBarHelper.error(
        context,
        ReleaseSearchNotifications.platformSupported
            ? 'Notifications are turned off for Cupola in system settings.'
            : 'Cupola cannot show notifications on this platform.',
      );
    }
  }

  /// Every release-search-capable service (Sonarr, Radarr, Lidarr) whose reach
  /// is [reach] — the sets this screen's global settings have to name rather
  /// than hedge, since each limit is per instance, not per app. At most three
  /// names each.
  List<ServiceKey> _servicesWithReach(ReleaseSearchReach reach) => ServiceKey
      .values
      .where(SearchHeadroomCard.appliesTo)
      .where((s) => ref.watch(releaseSearchLensReachProvider(s)) == reach)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(releaseSearchSettingsProvider);
    final notifier = ref.read(releaseSearchSettingsProvider.notifier);
    final pinnedServices = _servicesWithReach(
      ReleaseSearchReach.whileOpenTrustedCert,
    );
    final cleartextServices = _servicesWithReach(
      ReleaseSearchReach.whileOpenCleartext,
    );

    // The platform question comes first here for the same reason it comes first
    // in `reachFor`: where there is no background path, a switch would invent a
    // missing capability and a warning would attach to a risk that does not
    // exist.
    //
    // Read through `releaseSearchPlatformProvider` rather than from the host,
    // because that is the provider's whole purpose: `flutter_test` runs on a
    // desktop, so a direct `Platform` check would put every widget test on the
    // desktop branch and leave the switch — and the disclosure that is the
    // point of this screen — permanently unreachable from a test.
    final platform = ref.watch(releaseSearchPlatformProvider);
    final canRunInBackground = backgroundSearchSupported(platform: platform);
    // Resolved once, from the same source, and handed down: reading
    // `defaultTargetPlatform` inside the rows would make their copy report
    // Android under test no matter which platform the test is exercising.
    final isIOS = platform == null
        ? Platform.isIOS
        : platform == TargetPlatform.iOS;

    return AmbientScaffold(
      // The room belongs to the tab, not to the feature: this is a *settings*
      // pane that happens to be owned by release search, and left unset
      // `AmbientBackground` falls back to the brand indigo — Seerr's accent —
      // so the one pane the rail could not reach was also the one pane glowing
      // in a different colour from its six siblings.
      accent: NavTab.settings.accentColor,
      appBar: const GlassAppBar(title: Text('Background search')),
      // Background search is a section of the settings rail
      // (`SettingsMasterDetail.sections`), and it was the single destination in
      // that list not wrapped in the layout — a bare `GoRoute` rather than a
      // `_page`, rendering its body alone. On a desktop window that meant
      // selecting Background search made the rail *disappear*, so the one
      // control that got you here was the one control the page then hid: the
      // way back was the window's back gesture, from a list you were still
      // notionally standing in. The wrapper is inert below the rail threshold
      // and on every touch build, where Settings is correctly a drill-down.
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            if (canRunInBackground)
              SettingsGroupCard(
                children: [
                  _MasterRow(
                    enabled: settings.backgroundEnabled,
                    onChanged: _toggleBackground,
                  ),
                  _DisclosureBlock(isIOS: isIOS),
                ],
              )
            else
              const _DesktopStatusCard(),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroupCard(
              children: [
                _StepperRow(
                  icon: Icons.call_split_rounded,
                  title: 'At the same time',
                  subtitle: 'More is harder on rate-limited indexers',
                  value: '${settings.concurrency}',
                  range:
                      '${ReleaseSearchSettings.minConcurrency}'
                      '–${ReleaseSearchSettings.maxConcurrency}',
                  onDecrement:
                      settings.concurrency >
                          ReleaseSearchSettings.minConcurrency
                      ? () => notifier.setConcurrency(settings.concurrency - 1)
                      : null,
                  onIncrement:
                      settings.concurrency <
                          ReleaseSearchSettings.maxConcurrency
                      ? () => notifier.setConcurrency(settings.concurrency + 1)
                      : null,
                ),
                _StepperRow(
                  icon: Icons.schedule_rounded,
                  title: 'Give up after',
                  subtitle: 'Above every common proxy ceiling on purpose',
                  value: '${settings.timeout.inMinutes} min',
                  range:
                      '${ReleaseSearchSettings.minTimeout.inMinutes}'
                      '–${ReleaseSearchSettings.maxTimeout.inMinutes}',
                  onDecrement:
                      settings.timeout > ReleaseSearchSettings.minTimeout
                      ? () => notifier.setTimeoutMinutes(
                          settings.timeout.inMinutes - 1,
                        )
                      : null,
                  onIncrement:
                      settings.timeout < ReleaseSearchSettings.maxTimeout
                      ? () => notifier.setTimeoutMinutes(
                          settings.timeout.inMinutes + 1,
                        )
                      : null,
                ),
                _NotifyRow(
                  enabled: settings.notifyOnFinish,
                  busy: _asking,
                  // Nothing to announce when a search cannot outlive the app: the
                  // badge and the detail page already cover the in-app case.
                  // Disabled rather than reset — the preference (and the OS
                  // permission behind it) survives for when the master returns.
                  available: !canRunInBackground || settings.backgroundEnabled,
                  backgroundCapable: canRunInBackground,
                  systemPermission: ref
                      .watch(notificationPermissionProvider)
                      .value,
                  isIOS: isIOS,
                  foregroundOnlyServices: [
                    ...pinnedServices,
                    ...cleartextServices,
                  ],
                  onChanged: _toggleNotifications,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _LimitsCard(
              pinnedServices: pinnedServices,
              cleartextServices: cleartextServices,
              backgroundActive:
                  canRunInBackground && settings.backgroundEnabled,
            ),
          ],
        ),
      ),
    );
  }
}

/// The master switch: whether a search may be handed to the operating system.
///
/// Identical on iOS and Android by decision — the capability and the trade-off
/// are the same, and only the *detail* of where the OS keeps its copy differs,
/// which is what [_DisclosureBlock] varies. Absent on desktop, where
/// [_DesktopStatusCard] takes its place.
class _MasterRow extends StatelessWidget {
  const _MasterRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final Future<void> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const title = 'Background search';
    final subtitle = enabled
        ? 'A search keeps running after you leave the app.'
        : 'Searches end when you leave Cupola. Turn on to let them finish on '
              'their own.';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.cloud_sync_outlined,
              size: 18,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Semantics(
              container: true,
              label: '$title. $subtitle',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Switch(value: enabled, onChanged: (value) => onChanged(value)),
        ],
      ),
    );
  }
}

/// The trade-off, in two levels: one honest sentence, and the detail behind a
/// node the user can open.
///
/// Two levels rather than one wall of text, and an [ExpansionTile] rather than
/// an icon with a tooltip: the detail has to be reachable by a screen reader as
/// a labelled, expandable node, which an information glyph is not.
class _DisclosureBlock extends StatelessWidget {
  const _DisclosureBlock({required this.isIOS});

  /// Which OS's storage is being described. Passed in rather than read from the
  /// host so both variants are reachable from a test — the copy *is* the
  /// feature here, and untestable copy is copy that drifts.
  final bool isIOS;

  /// The same sentence on both platforms, because the fact is the same one.
  static const headline =
      'While Cupola is suspended, the system runs the search on its behalf, '
      'so the request, including this service\'s admin API key, sits in system '
      'storage while the task runs.';

  /// Where that copy lives, and what covers it, differs by OS — so this is the
  /// half that is written twice. Both name the key plainly: it is administrative,
  /// which is the whole reason any of this matters.
  static String detailsFor({required bool isIOS}) {
    if (isIOS) {
      return "The system's working copy never leaves this device and is deleted "
          'when the search ends, after '
          '${kBackgroundSearchResourceTimeout.inMinutes} minutes at the latest. '
          'If iOS closes Cupola before it can collect a result, that result '
          'waits, key included, in the app\'s preferences until the next '
          'launch, and preferences are part of device backups: an encrypted '
          'Finder backup, or iCloud with Advanced Data Protection, covers that '
          'copy. Turning this off cancels running background searches and '
          'clears the stored records.';
    }
    return "The system's copies live in app-private storage that is excluded "
        'from every backup, reading them takes a rooted device. Cupola clears '
        'finished records at every launch. Turning this off cancels running '
        'background searches and clears the stored records right away.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          Theme(
            // The tile is inside a card that already draws its own divisions.
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'What is stored, and for how long',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detailsFor(isIOS: isIOS),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop's answer in place of the switch: a statement, not a control.
///
/// macOS, Windows and Linux share one sentence because they share the reason —
/// nothing suspends the app, so nothing is ever handed to the OS and no record
/// exists to warn about. A switch here would advertise a capability as missing
/// when it is simply always on, and a disclosure would attach a risk to a
/// platform that does not carry it.
class _DesktopStatusCard extends StatelessWidget {
  const _DesktopStatusCard();

  static const message =
      'Searches keep running while Cupola is open, desktop never suspends the '
      'app, so nothing is handed to the system and nothing is written to '
      'system storage.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AppCard.surfaceOutlined(
      child: Semantics(
        container: true,
        label: 'Background search. $message',
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.desktop_mac_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one notification setting, and the only place permission is ever asked for.
class _NotifyRow extends StatelessWidget {
  const _NotifyRow({
    required this.enabled,
    required this.busy,
    required this.available,
    required this.backgroundCapable,
    required this.systemPermission,
    required this.isIOS,
    required this.foregroundOnlyServices,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;

  /// Whether the setting can do anything at all right now. False only when the
  /// master switch is off on a platform that has one.
  final bool available;

  /// Whether this platform has a background path at all — which is what
  /// separates "not needed here" from "needs the master switch".
  final bool backgroundCapable;

  /// What the OS says right now: true granted, false denied, null unknown.
  ///
  /// Shown because the app's own preference and the system permission drift
  /// apart silently — a permission revoked in system settings leaves the toggle
  /// on and every notice dropped, which reads as a broken feature rather than a
  /// withdrawn permission.
  final bool? systemPermission;

  /// Which OS to name in the denial route. Passed in for the same reason
  /// [_DisclosureBlock.isIOS] is.
  final bool isIOS;

  /// Release-search services whose background reach is cut off by something
  /// about the instance itself — a certificate trusted only inside Cupola, or
  /// a cleartext origin. Both land in the same sentence because the user-facing
  /// consequence is identical: a search that stops when they leave the app.
  /// See [ReleaseSearchReach].
  final List<ServiceKey> foregroundOnlyServices;
  final Future<void> Function(bool value) onChanged;

  String get _subtitle {
    if (!available) {
      return 'Needs Background search, a search that ends with the app has '
          'nothing to announce';
    }
    if (!backgroundCapable) {
      return 'Not needed here, the app keeps running';
    }
    if (foregroundOnlyServices.isEmpty) {
      return 'Only when Cupola is not in front of you';
    }
    final names = foregroundOnlyServices.map((s) => s.title).join(', ');
    return 'Only when Cupola is not in front of you, for $names, that '
        "includes a search stopping because it couldn't keep running in the "
        'background';
  }

  /// The system's own answer, said only when it adds something.
  ///
  /// Silent while unknown — a platform with no branch for this, or a plugin that
  /// is not there — because "unknown" rendered as a status is worse than no
  /// status at all. Silent too when the row is disabled by the master switch:
  /// the row already explains itself, and a second sentence about a permission
  /// that currently changes nothing is noise. A denial names the route rather
  /// than just the problem.
  String? get _permissionLine {
    if (!available) return null;
    return switch (systemPermission) {
      true => 'System permission: granted',
      false =>
        isIOS
            ? 'Blocked in Settings › Notifications › Cupola'
            : "Blocked in your system's notification settings",
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              size: 18,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tell me when one finishes',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  _subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (_permissionLine case final line?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                        // The status vocabulary's own amber, not `tertiary` —
                        // which in this theme is a palette accent and rendered
                        // a blocked permission in green. Amber rather than red
                        // because a permission the user can switch back on is
                        // something to fix, not something that failed.
                        color: systemPermission == false
                            ? AppColors.warning
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: enabled && available,
              onChanged: available ? (value) => onChanged(value) : null,
            ),
        ],
      ),
    );
  }
}

/// What this cannot do, said plainly and before it bites.
class _LimitsCard extends StatelessWidget {
  const _LimitsCard({
    required this.pinnedServices,
    required this.cleartextServices,
    required this.backgroundActive,
  });

  /// Whether searches can currently be handed to the OS at all.
  ///
  /// What it gates is every limit that only exists *because* of background
  /// execution — the app-killed loss, the Android ceiling, the per-instance
  /// downgrades. Listing those while the feature is off would describe a mode
  /// the user is not in; the grab window and the privacy line are true either
  /// way and stay.
  final bool backgroundActive;

  /// Release-search services whose background reach is cut off by a
  /// certificate trusted only inside Cupola — see [ReleaseSearchReach].
  final List<ServiceKey> pinnedServices;

  /// Release-search services whose background reach is cut off because they
  /// are reached over cleartext `http://` — see [ReleaseSearchReach]. Kept
  /// apart from [pinnedServices] because the fix is a different one.
  final List<ServiceKey> cleartextServices;

  /// Only stated where it is true, rather than hedged everywhere — and only
  /// while the ceiling can actually be hit.
  bool get androidCeilingApplies =>
      backgroundActive && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );

    return AppCard.surfaceOutlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What this can't do", style: theme.textTheme.titleSmall),
          line(
            'Found releases stay grabbable for '
            '${kGrabWindow.inMinutes} minutes. That is the service\'s own limit, '
            'not a setting here, after it, grabbing needs a fresh search.',
          ),
          line(
            backgroundActive
                ? 'A search keeps going when you switch apps, but if Cupola is '
                      'closed while it waits, by you or by the system reclaiming '
                      'memory, the outcome is lost: no notification, and nothing '
                      'under Activity. Searching again is the only recovery.'
                : 'A search runs as long as Cupola is running. Leaving the app '
                      'ends it.',
          ),
          if (androidCeilingApplies)
            line(
              'Android stops background work after '
              '${BackgroundReleaseSearchTransport.androidCeiling.inMinutes} '
              'minutes. A longer search needs Cupola open, where there is no '
              'ceiling.',
            ),
          if (pinnedServices.isNotEmpty)
            line(
              '${pinnedServices.map((s) => s.title).join(', ')} '
              '${pinnedServices.length == 1 ? 'uses' : 'use'} a certificate '
              "trusted only inside Cupola, so ${pinnedServices.length == 1 ? 'its' : 'their'} "
              'searches run in the foreground instead of the background, see '
              "that service's connection in Settings for how to restore it.",
            ),
          if (cleartextServices.isNotEmpty)
            line(
              '${cleartextServices.map((s) => s.title).join(', ')} '
              '${cleartextServices.length == 1 ? 'is' : 'are'} reached over '
              'plain http, so ${cleartextServices.length == 1 ? 'its' : 'their'} '
              'searches run in the foreground instead of the background: a '
              'background search cannot refuse a redirect, and over http '
              'anyone on the network can inject one to collect the API key. '
              'Switching to https restores it.',
            ),
          line(
            'Nothing is searched on a server of ours, there is not one. Your '
            'own instances do the work, and what Cupola measures about them '
            'never leaves this device.',
          ),
        ],
      ),
    );
  }
}

/// A settings row whose value is a small integer.
///
/// Two buttons rather than a slider: the useful range is four steps wide, and a
/// slider would give a coarse gesture control over a value where every step
/// matters to someone's indexers.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.range,
    this.onDecrement,
    this.onIncrement,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final String range;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    void tap(VoidCallback? action) {
      if (action == null) return;
      HapticFeedback.selectionClick();
      action();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: colors.primary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Semantics(
              container: true,
              label: '$title, $value. $subtitle. Range $range.',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            enabled: onDecrement != null,
            label: 'Decrease $title',
            onTap: onDecrement == null ? null : () => tap(onDecrement),
            excludeSemantics: true,
            child: IconButton(
              onPressed: onDecrement == null ? null : () => tap(onDecrement),
              icon: const Icon(Icons.remove_rounded, size: 18),
              tooltip: 'Decrease $title',
            ),
          ),
          // Tabular so the row does not shift as the figure changes width.
          Text(value, style: theme.textTheme.titleSmall?.tabular),
          Semantics(
            button: true,
            enabled: onIncrement != null,
            label: 'Increase $title',
            onTap: onIncrement == null ? null : () => tap(onIncrement),
            excludeSemantics: true,
            child: IconButton(
              onPressed: onIncrement == null ? null : () => tap(onIncrement),
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: 'Increase $title',
            ),
          ),
        ],
      ),
    );
  }
}
