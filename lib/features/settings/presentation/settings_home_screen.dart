import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/home/presentation/widgets/settings_home_row.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_app_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/requester_settings_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_summary_cards.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

export 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart'
    show SettingsSectionLabel;

/// `/settings`, which is two things at one address.
///
/// On a window wide enough for the rail it is the **summary pane**: six cards,
/// one per area, each the door to its own page and each printing only what is
/// wrong there. It is the only row on that rail that is a readout rather than a
/// form, which is why it is called Overview.
///
/// Below that width there is no rail to be the index, so this route *is* the
/// index: the same connections card at the top, the one thing that can be
/// wrong rather than merely set, and under it the doors, grouped. One route,
/// one URL, a deep link that resolves the same on both.
class SettingsHomeScreen extends ConsumerWidget {
  const SettingsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final padding = EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      FloatingNavBarMetrics.getScrollViewBottomPadding(context),
    );

    // The tab Settings was opened from, and the way back to it: the page is a
    // branch root with nothing to pop. Not in the desktop window, where
    // Settings is an item of the rail and the rail is the way back.
    final from = AppBreakpoints.isDesktopShell(context)
        ? null
        : ref.watch(settingsReturnProvider);
    void goBack() {
      ref.read(settingsReturnProvider.notifier).set(null);
      StatefulNavigationShell.maybeOf(context)?.goBranch(from!.index);
    }

    final page = AmbientScaffold(
      // No accent: a settings pane has no artwork, so its room is lit by the
      // neutral lamp, the fallback of `AmbientBackground`.
      appBar: GlassAppBar(
        title: const Text('Settings'),
        leading: from == null
            ? null
            : IconButton(
                tooltip: 'Back to ${from.label}',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: goBack,
              ),
      ),
      body: SettingsMasterDetail(
        // Asked of the layout itself rather than re-derived here, so the pane
        // and the rail can never disagree about which of the two is on screen.
        child: SettingsMasterDetail.showsRail(context)
            ? SettingsSummaryPane(padding: padding)
            : ListView(
                padding: padding,
                children: ref.watch(shellAudienceProvider) == Audience.requester
                    ? _requesterIndex(context, settings)
                    : [
                        const ConnectionsSummaryCard(),
                        const SizedBox(height: AppSpacing.xl),
                        ..._buildGeneralSection(context, settings),
                        const SizedBox(height: AppSpacing.xl),
                        ..._buildSecuritySection(context, settings),
                        const SizedBox(height: AppSpacing.xl),
                        ..._buildAboutSection(context),
                        const SizedBox(height: AppSpacing.xl),
                        ..._buildDangerZoneSection(),
                      ],
              ),
      ),
    );
    if (from == null) return page;
    // Android's back, which on a branch root would otherwise leave the app
    // (the shell claims it for this page). Only while this page is the one on
    // top: a pushed settings page pops first, through its own navigator, and
    // a tab tapped from here leaves the page built in its branch, where its
    // route is still its navigator's current one.
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
        final shell = StatefulNavigationShell.maybeOf(context);
        if (shell != null && shell.currentIndex != NavTab.settings.index) {
          return false;
        }
        goBack();
        return true;
      },
      child: page,
    );
  }

  /// The requester's Settings (the spec of the requester, § 6.2): her
  /// account, what she sets for herself, the app, and last the one way into
  /// the operator's app. None of the operator's rows: no connections, release
  /// search, trust store, onboarding replay or reset, and no Hints, which
  /// teach the Portal her app has not.
  List<Widget> _requesterIndex(BuildContext context, SettingsModel settings) {
    return [
      const RequesterAccountCard(),
      const SizedBox(height: AppSpacing.xl),
      const SettingsSectionLabel('General'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          _regionRow(context, settings),
          _appearanceRow(context, settings),
          const SettingsHomeRow(),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
      const SettingsSectionLabel('About'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: settingsAboutRows(context, audience: Audience.requester),
      ),
      const SizedBox(height: AppSpacing.xl),
      const SettingsGroupCard(children: [SetUpAServiceRow()]),
    ];
  }

  Widget _regionRow(BuildContext context, SettingsModel settings) =>
      SettingsCard.grouped(
        leading: const Icon(Icons.language_rounded),
        title: 'Region',
        subtitle: _formatRegionLabel(settings.region),
        semanticHint: 'opens the region picker',
        onTap: () => context.push('/settings/region'),
      );

  Widget _appearanceRow(BuildContext context, SettingsModel settings) =>
      SettingsCard.grouped(
        leading: const Icon(Icons.palette_rounded),
        title: 'Appearance',
        subtitle: settings.themeMode.label,
        semanticHint: 'opens the appearance picker',
        onTap: () => context.push('/settings/appearance'),
      );

  List<Widget> _buildGeneralSection(
    BuildContext context,
    SettingsModel settings,
  ) {
    return [
      const SettingsSectionLabel('General'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          // None of these five carries an accent. The accent slot on a settings
          // row is the status slot; it is where the connections card puts the
          // verdict, and Region wore `AppColors.success` while Send feedback
          // wore the amber this system reserves for a fault. A preference has
          // no state to report.
          _regionRow(context, settings),
          _appearanceRow(context, settings),
          const SettingsHomeRow(),
          SettingsCard.grouped(
            leading: const Icon(Icons.travel_explore_rounded),
            title: 'Background search',
            subtitle: 'How long to wait, and how many at once',
            semanticHint: 'opens background release search settings',
            onTap: () => context.push('/settings/background-search'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.tips_and_updates_outlined),
            title: 'Hints',
            subtitle: 'Nudges that introduce a gesture',
            semanticHint: 'opens the gesture hint switches',
            onTap: () => context.push('/settings/hints'),
          ),
          // Shared with the window's summary pane: see settings_app_rows.dart.
          const SettingsRevisitOnboardingRow(),
        ],
      ),
    ];
  }

  /// Trusted certificates, always, not only when something is pinned.
  ///
  /// It used to be reachable from exactly one place: a row on the Connections
  /// screen that appears only when the map is non-empty. The rail carries it on
  /// a window, and the phone has no rail, so on a phone with nothing pinned yet
  /// the pane did not exist at all. Trust is per origin and outlives the
  /// services that created it (ADR-6), which is precisely why the door has to
  /// stand even when the room is empty.
  List<Widget> _buildSecuritySection(
    BuildContext context,
    SettingsModel settings,
  ) {
    return [
      const SettingsSectionLabel('Security'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.verified_user_outlined),
            title: 'Trusted certificates',
            subtitle: 'Pinned by address, not by service',
            semanticHint: 'opens the trusted certificates list',
            onTap: () => context.push('/settings/certificates'),
          ),
          // Keys and certificates are what it moves: the group before About.
          if (SettingsAnotherDeviceRow.offeredFor(settings))
            const SettingsAnotherDeviceRow(),
        ],
      ),
    ];
  }

  // About and Danger zone build the same rows the window's summary pane does
  // (settings_app_rows.dart): they are not pages, so the rail cannot carry
  // them, and while only this index built them a wide window had no door to
  // the licence page, feedback, the donation sheet or Reset.
  List<Widget> _buildAboutSection(BuildContext context) {
    return [
      const SettingsSectionLabel('About'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(children: settingsAboutRows(context)),
    ];
  }

  List<Widget> _buildDangerZoneSection() {
    return const [
      SettingsSectionLabel('Danger zone'),
      SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(children: [SettingsResetAppDataRow()]),
    ];
  }

  String _formatRegionLabel(String region) {
    final normalizedRegion = SettingsModel.normalizeRegion(region);
    final regionName = commonRegions[normalizedRegion] ?? normalizedRegion;
    return '$regionName ($normalizedRegion)';
  }
}
