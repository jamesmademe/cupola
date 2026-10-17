import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/unread_secret.dart';

/// Shown where a service has no address or credentials stored yet.
///
/// Built on [AppEmptyState] rather than as its own layout, because a service you
/// have not set up is a normal daily condition, not a fault: the app is meant to
/// have more integrations than anybody runs at once. It used to paint a
/// 64pt settings glyph in `colorScheme.error`: alarm chrome for a state the user
/// created on purpose by not filling in a form, and `AppEmptyState`'s own doc
/// already named this placeholder as one of the states it exists to unify.
class NotConfiguredPlaceholder extends StatelessWidget {
  /// The generic form, for callers that know only the service's display name:
  /// notably [AsyncValueWidget] and [MediaDetailPlaceholderView], which reach
  /// this state from a `ServiceNotConfigured` throw and draw it under the name
  /// their caller gave them. The name is resolved back to its service, so
  /// its button is the same `Set up X` into the same form; only a name that is
  /// no service's lands on the Settings root.
  const NotConfiguredPlaceholder({super.key, required this.serviceName})
    : service = null;

  /// The form a service dashboard should use: the button deep-links to that
  /// service's own settings page instead of the Settings root.
  ///
  /// This is not cosmetic. The private per-dashboard copies this widget
  /// replaced all navigated to `/settings/service/<routeParam>`, and collapsing
  /// them onto the generic constructor silently downgraded four screens to
  /// "here is Settings, go find it yourself". The per-service page is also where
  /// [ServiceKey.setupNote] is rendered, so the guidance those copies printed
  /// inline (Unraid's plugin before 7.2, Plex's token flavour) is one tap away and
  /// stated once rather than duplicated per surface.
  // `ServiceKey this.service` rather than a plain `this.service`: the field is
  // nullable for the generic form, and narrowing the formal here is what keeps
  // this constructor's promise that there IS a service.
  NotConfiguredPlaceholder.forService(ServiceKey this.service, {super.key})
    : serviceName = service.title;

  final String serviceName;

  /// Null for the generic form; set by [NotConfiguredPlaceholder.forService].
  final ServiceKey? service;

  /// The service this names: the key it was given, or the one whose title
  /// the generic form was handed: `AsyncValueWidget` passes the name its
  /// caller gave it.
  ServiceKey? get _resolved {
    final key = service;
    if (key != null) return key;
    for (final candidate in ServiceKey.values) {
      if (candidate.title == serviceName) return candidate;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final key = _resolved;
    // A connection whose secret secure storage would not hand over is set
    // up, and unusable until it is pasted again: it says so, amber, with the
    // way into its own form, never `Set up Radarr`.
    if (key != null && _scoped(context)) {
      return Consumer(
        builder: (context, ref, _) {
          final unread = _unreadConnection(ref, key);
          if (unread != null) {
            return UnreadSecretState(
              instance: unread,
              connectionName: _connectionName(ref, unread),
            );
          }
          return _signedOutOrNotSetUp(context, ref, key);
        },
      );
    }
    return _notSetUp(context, key);
  }

  Widget _signedOutOrNotSetUp(
    BuildContext context,
    WidgetRef ref,
    ServiceKey key,
  ) {
    // A Seerr account whose session ended is set up, and signed out: it reads
    // so, blue, with the way back into its own form, never `Set up Seerr`.
    // Only inside a ProviderScope, which the app always has: a bare test of
    // this widget has no settings to read.
    if (key == ServiceKey.seerr) {
      const seerr = ServiceKey.seerr;
      final signedOut = _signedOutSeerr(ref);
      if (signedOut == null) return _notSetUp(context, seerr);
      return AppErrorState(
        service: seerr,
        instanceId: signedOut.id,
        error: const ClassifiedFailure(ServiceFailureReason.sessionEnded),
      );
    }
    return _notSetUp(context, key);
  }

  /// The connection of [service] this screen stands on whose secret could
  /// not be read, or null; null too in a scope with no settings in it.
  static ServiceInstance? _unreadConnection(WidgetRef ref, ServiceKey service) {
    try {
      final lensId = ref.watch(activeInstanceProvider(service))?.id;
      return ref.watch(
        currentSettingsProvider.select(
          (settings) => settings.unreadConnectionOf(service, lensId: lensId),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// The connection's own name where the service has more than one.
  static String? _connectionName(WidgetRef ref, ServiceInstance instance) {
    try {
      return ref.watch(
        currentSettingsProvider.select(
          (settings) => settings.connectionName(instance.id),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _scoped(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The signed-out Seerr connection this screen stands on, or null. A scope
  /// with no settings in it (a test that overrides something else) has none.
  static ServiceInstance? _signedOutSeerr(WidgetRef ref) {
    try {
      final lensId = ref.watch(activeInstanceProvider(ServiceKey.seerr))?.id;
      return ref.watch(
        currentSettingsProvider.select(
          (settings) =>
              settings.signedOutConnectionOf(ServiceKey.seerr, lensId: lensId),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _notSetUp(BuildContext context, ServiceKey? key) {
    return AppEmptyState(
      icon: Icons.settings_outlined,
      // The same voice as the rest of the app's connection states, which say a
      // service "did not answer" rather than reporting a config condition.
      title: Lexicon.isNotSetUp(serviceName),
      // "Credentials" rather than "the URL and API Key": four of the thirteen
      // services authenticate with a WebUI login and have no API key to paste, so
      // naming one told a third of the roster to look for a field that is not
      // there. The "Please" went with it: the UI is not asking a favour.
      message: "Add its address and credentials in Settings.",
      // `Set up X`, to the service's own setup form: the one place every
      // way in goes. Only a name that is no service keeps the Settings root.
      // Pushed, not gone to: the form's back and its Save return to the page
      // that asked, where a `go` left the person in Settings.
      action: FilledButton.icon(
        onPressed: () => context.push(
          key == null ? ServiceRoutes.settings : ServiceRoutes.setUp(key),
        ),
        icon: const Icon(Icons.add_link_rounded, size: 18),
        label: Text(key == null ? 'Open Settings' : Lexicon.setUp(key.title)),
      ),
    );
  }
}

/// A screen standing on a connection whose secret could not be read: what
/// happened on this device, and the way to paste it again.
///
/// The anatomy of [AppErrorState]'s page form, amber: the secret is a fault
/// of this device's storage, not of the service, and nothing was sent.
class UnreadSecretState extends StatelessWidget {
  const UnreadSecretState({
    super.key,
    required this.instance,
    this.connectionName,
  });

  final ServiceInstance instance;
  final String? connectionName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = UnreadSecretWords.of(
      instance,
      connectionName: connectionName,
    );
    final amber = statusToneColor(theme.colorScheme, StatusTone.warning);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_off_rounded, size: 32, color: amber),
            const SizedBox(height: AppSpacing.lg),
            Text(
              words.headline,
              style: theme.textTheme.titleMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: amber),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              words.sentence,
              style: theme.textTheme.labelSmall?.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () => context.go(words.route),
              style: remedyFillStyle(context),
              child: Text(words.remedy),
            ),
          ],
        ),
      ),
    );
  }
}
