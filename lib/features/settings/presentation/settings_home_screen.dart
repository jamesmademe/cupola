import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/donation_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/domain/trademark_notice.dart';
import 'package:cupola/features/settings/presentation/widgets/donation_sheet.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_summary_cards.dart';

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
/// index: the same connections card at the top — the one thing that can be
/// wrong rather than merely set — and under it the doors, grouped. One route,
/// one URL, a deep link that resolves the same on both.
class SettingsHomeScreen extends ConsumerWidget {
  const SettingsHomeScreen({super.key});

  static final Uri _githubUri = Uri.parse(
    'https://github.com/matthw-labs/seekarr',
  );
  static final Uri _feedbackUri = Uri(
    scheme: 'mailto',
    path: 'matthw.labs@gmail.com',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final padding = EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      FloatingNavBarMetrics.getScrollViewBottomPadding(context),
    );

    return AmbientScaffold(
      // The room belongs to the tab, and the tab's accent is teal. Left unset,
      // `AmbientBackground` falls back to `colorScheme.primary` — the brand
      // indigo — so every settings pane glowed in Seerr's colour.
      accent: NavTab.settings.accentColor,
      appBar: const GlassAppBar(title: Text('Settings')),
      body: SettingsMasterDetail(
        // Asked of the layout itself rather than re-derived here, so the pane
        // and the rail can never disagree about which of the two is on screen.
        child: SettingsMasterDetail.showsRail(context)
            ? SettingsSummaryPane(padding: padding)
            : ListView(
                padding: padding,
                children: [
                  const ConnectionsSummaryCard(),
                  const SizedBox(height: AppSpacing.xl),
                  ..._buildGeneralSection(context, ref, settings),
                  const SizedBox(height: AppSpacing.xl),
                  ..._buildSecuritySection(context),
                  const SizedBox(height: AppSpacing.xl),
                  ..._buildAboutSection(context),
                  const SizedBox(height: AppSpacing.xl),
                  ..._buildDangerZoneSection(context, ref),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildGeneralSection(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) {
    return [
      const SettingsSectionLabel('General'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          // None of these five carries an accent. The accent slot on a settings
          // row is the status slot — it is where the connections card puts the
          // verdict — and Region wore `AppColors.success` while Send feedback
          // wore the amber this system reserves for a fault. A preference has
          // no state to report.
          SettingsCard.grouped(
            leading: const Icon(Icons.language_rounded),
            title: 'Region',
            subtitle: _formatRegionLabel(settings.region),
            semanticHint: 'opens the region picker',
            onTap: () => context.push('/settings/region'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.palette_rounded),
            title: 'Appearance',
            subtitle: settings.themeMode.label,
            semanticHint: 'opens the appearance picker',
            onTap: () => context.push('/settings/appearance'),
          ),
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
          SettingsCard.grouped(
            leading: const Icon(Icons.replay_rounded),
            title: 'Revisit onboarding',
            subtitle: 'Walk through the intro screens again',
            semanticHint: 'restarts the onboarding flow for this session',
            onTap: () => _confirmRevisitOnboarding(context, ref),
          ),
        ],
      ),
    ];
  }

  /// Trusted certificates, always — not only when something is pinned.
  ///
  /// It used to be reachable from exactly one place: a row on the Connections
  /// screen that appears only when the map is non-empty. The rail carries it on
  /// a window, and the phone has no rail, so on a phone with nothing pinned yet
  /// the pane did not exist at all. Trust is per origin and outlives the
  /// services that created it (ADR-6), which is precisely why the door has to
  /// stand even when the room is empty.
  List<Widget> _buildSecuritySection(BuildContext context) {
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
        ],
      ),
    ];
  }

  List<Widget> _buildAboutSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      const SettingsSectionLabel('About'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.code_rounded),
            title: 'GitHub',
            subtitle: 'Source, issues and releases',
            accentColor: colorScheme.onSurfaceVariant,
            semanticHint: 'opens the repository in your browser',
            onTap: () => _openGitHub(context),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.feedback_rounded),
            title: 'Send feedback',
            subtitle: 'Email the developer',
            semanticHint: 'opens your email composer',
            onTap: () => _sendFeedback(context),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.favorite_rounded),
            title: 'Support development',
            subtitle: 'Buy me a coffee',
            onTap: () => _openDonation(context),
          ),
          // The only way into the licence page. `main.dart` registers Inter's
          // OFL with the registry, and the OFL's one condition on a bundling
          // binary is that its text travels with it — which it did not, in
          // any build, while nothing in the app opened the page.
          SettingsCard.grouped(
            leading: const Icon(Icons.gavel_rounded),
            title: 'Licenses & trademarks',
            subtitle: 'Open-source licenses and trademark notices',
            accentColor: colorScheme.onSurfaceVariant,
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Cupola',
              applicationLegalese: trademarkNotice,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildDangerZoneSection(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      const SettingsSectionLabel('Danger zone'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.restart_alt_rounded),
            title: 'Reset app data',
            subtitle: 'Clear all services, settings, and restart onboarding',
            accentColor: colorScheme.error,
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    ];
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.warning_amber_rounded,
      title: 'Reset all data?',
      message:
          'This clears all saved services, credentials, and preferences. '
          'Onboarding will restart. This cannot be undone.',
      confirmLabel: 'Reset',
      destructive: true,
    );

    if (!result.confirmed) return;

    try {
      await ref.read(settingsProvider.notifier).resetSettings();
      await markOnboardingIncomplete(ref);
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, "Couldn't reset app data.", detail: e);
    }
  }

  Future<void> _confirmRevisitOnboarding(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.replay_rounded,
      title: 'Revisit onboarding?',
      message:
          "You'll go through the intro screens again for this session. "
          'Nothing about your services or settings is changed or removed.',
      confirmLabel: 'Continue',
    );

    if (!result.confirmed) return;

    await markOnboardingIncomplete(ref);
    if (!context.mounted) return;
    context.go('/onboarding');
  }

  String _formatRegionLabel(String region) {
    final normalizedRegion = SettingsModel.normalizeRegion(region);
    final regionName = commonRegions[normalizedRegion] ?? normalizedRegion;
    return '$regionName ($normalizedRegion)';
  }

  Future<void> _openGitHub(BuildContext context) {
    return _launchExternalUri(
      context: context,
      uri: _githubUri,
      failureMessage: 'Unable to open the GitHub repository.',
    );
  }

  Future<void> _sendFeedback(BuildContext context) {
    return _launchExternalUri(
      context: context,
      uri: _feedbackUri,
      failureMessage: 'Unable to open the email composer.',
    );
  }

  Future<void> _openDonation(BuildContext context) async {
    if (DonationService.usesIAP) {
      final useFallback = await AppBottomSheet.show<bool>(
        context: context,
        title: 'Support Cupola',
        icon: Icons.favorite_rounded,
        builder: (_) => const DonationSheet(),
      );
      // Sheet returned true when IAP products aren't available — open Ko-fi.
      if (useFallback == true && context.mounted) {
        final launched = await DonationService.launchKofi();
        if (!launched && context.mounted) {
          SnackBarHelper.info(context, 'Unable to open the donation page.');
        }
      }
    } else {
      final launched = await DonationService.launchKofi();
      if (!launched && context.mounted) {
        SnackBarHelper.info(context, 'Unable to open the donation page.');
      }
    }
  }

  Future<void> _launchExternalUri({
    required BuildContext context,
    required Uri uri,
    required String failureMessage,
  }) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      SnackBarHelper.info(context, failureMessage);
    }
  }
}
