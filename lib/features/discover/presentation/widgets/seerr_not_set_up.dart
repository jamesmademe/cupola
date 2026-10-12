import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/media_detail_placeholder_view.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// Whether there is a Seerr to ask: the question every Seerr page settles
/// **before** it reads a provider.
///
/// Asked first because the other order is a failure that cannot heal. A
/// provider that reaches for an unconfigured Seerr throws, a provider that
/// throws is a failed provider, and a failed provider is retried on a backoff
/// for a condition no amount of waiting changes: the film page's lookup was
/// asked again ten times over forty seconds, under a placeholder that already
/// said there was nothing to ask.
///
/// The lens, because that is the connection every Seerr provider on these pages
/// reads (`seerrServiceProvider` resolves it). A `select`, so the page rebuilds
/// when that answer changes and not on every unrelated settings write.
bool watchSeerrConfigured(WidgetRef ref) => ref.watch(
  activeInstanceProvider(
    ServiceKey.seerr,
  ).select((instance) => instance?.isConfigured ?? false),
);

/// The page a Seerr detail route draws when there is no Seerr to ask:
/// *Seerr is not set up*, and the one *Set up Seerr* into its own form.
///
/// The same room the loaded page wears, so a deep link into a title on a stack
/// without Seerr lands on the same chrome with the fix in it.
class SeerrDetailNotSetUpView extends StatelessWidget {
  const SeerrDetailNotSetUpView({super.key});

  @override
  Widget build(BuildContext context) {
    return MediaDetailPlaceholderView.error(
      // The missing-config marker, which the placeholder turns into "Seerr is
      // not set up" and its "Set up Seerr". No Retry: the fix is a form, and
      // asking again would only ask nobody.
      error: const ServiceNotConfigured(ServiceKey.seerr),
      serviceName: ServiceKey.seerr.title,
      accent: ServiceKey.seerr.accent,
    );
  }
}
