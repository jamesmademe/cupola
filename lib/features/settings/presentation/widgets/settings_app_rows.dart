import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/donation_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/trademark_notice.dart';
import 'package:cupola/features/settings/presentation/widgets/donation_sheet.dart';

/// The rows about the app rather than about the stack: About, Revisit
/// onboarding, Reset app data.
///
/// **One set, two layouts.** They lived only in the phone index
/// (`SettingsHomeScreen`), so on a window wide enough for the rail — where
/// `/settings` is the summary pane and every other row became a rail section —
/// the licence page, the feedback address, the donation sheet, the onboarding
/// replay and Reset had no door at all. None of them is a page, so none belongs
/// on the rail; the pane shows them as cards in its own grammar, and both
/// layouts build the same rows from here so they cannot drift.

final Uri _githubUri = Uri.parse('https://github.com/matthw-labs/seekarr');
final Uri _feedbackUri = Uri(scheme: 'mailto', path: 'matthw.labs@gmail.com');

/// GitHub, Send feedback, Support development, Licenses & trademarks — the
/// four rows of the About group, in that order.
List<Widget> settingsAboutRows(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return [
    SettingsCard.grouped(
      leading: const Icon(Icons.code_rounded),
      title: 'GitHub',
      subtitle: 'Source, issues and releases',
      accentColor: colorScheme.onSurfaceVariant,
      semanticHint: 'opens the repository in your browser',
      onTap: () => _launchExternalUri(
        context: context,
        uri: _githubUri,
        failureMessage: 'Unable to open the GitHub repository.',
      ),
    ),
    SettingsCard.grouped(
      leading: const Icon(Icons.feedback_rounded),
      title: 'Send feedback',
      subtitle: 'Email the developer',
      semanticHint: 'opens your email composer',
      onTap: () => _launchExternalUri(
        context: context,
        uri: _feedbackUri,
        failureMessage: 'Unable to open the email composer.',
      ),
    ),
    SettingsCard.grouped(
      leading: const Icon(Icons.favorite_rounded),
      title: 'Support development',
      subtitle: 'Buy me a coffee',
      onTap: () => _openDonation(context),
    ),
    // The only way into the licence page. `main.dart` registers each bundled
    // font's OFL with the registry, and the OFL's one condition on a bundling
    // binary is that its text travels with it — which it did not, in any
    // build, while nothing in the app opened the page.
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
  ];
}

/// Walks the intro screens again, after asking.
class SettingsRevisitOnboardingRow extends ConsumerWidget {
  const SettingsRevisitOnboardingRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsCard.grouped(
      leading: const Icon(Icons.replay_rounded),
      title: 'Revisit onboarding',
      subtitle: 'Walk through the intro screens again',
      semanticHint: 'restarts the onboarding flow for this session',
      onTap: () => _confirmRevisitOnboarding(context, ref),
    );
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
      confirmLabel: 'Revisit onboarding',
    );

    if (!result.confirmed) return;

    await markOnboardingIncomplete(ref);
    if (!context.mounted) return;
    context.go('/onboarding');
  }
}

/// Clears every service, credential and preference — behind its confirmation,
/// on both layouts.
class SettingsResetAppDataRow extends ConsumerWidget {
  const SettingsResetAppDataRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsCard.grouped(
      leading: const Icon(Icons.restart_alt_rounded),
      title: 'Reset app data',
      subtitle: 'Clear all services, settings, and restart onboarding',
      // The row's default accent, like every other settings row: red means
      // unreachable and nothing else, and the confirmation says what goes.
      onTap: () => _confirmReset(context, ref),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.restart_alt_rounded,
      title: 'Reset all data?',
      message:
          'This clears all saved services, credentials, and preferences. '
          'Onboarding will restart. This cannot be undone.',
      confirmLabel: 'Reset app data',
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
