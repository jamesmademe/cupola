import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// A tab that is on its service's bar but whose data the app cannot fetch yet.
///
/// Every tab a service has gets a branch from the first day the bar draws it,
/// which is why this exists. The bar is generated from `tabsFor`, so a tab
/// without a branch is an index that selects nothing, a bar and a router
/// disagreeing, which is worse than a view that admits it is not built.
///
/// It wears the *empty* archetype and not an error one, deliberately: nothing
/// failed. The States sheet is explicit that in a self-hosted stack none of the
/// resting conditions uses alarm chrome, so this is the same 72dp well the queue
/// shows when the queue is genuinely empty.
///
/// Two states, not one. A service that is not set up answers first, because
/// "the Calendar is empty" would be a claim about a server this app has never
/// spoken to: the emptiness of a thing you cannot see is not a fact.
///
/// **No route reaches this today.** Every tab on every bar now resolves to a
/// screen, so the only callers left are the tests that keep this honest. It is
/// kept rather than deleted because the invariant it serves has not gone away:
/// `tabsFor` is the bar, the router's wildcard throws on a tab it does not
/// know, and the day a tab is added to that table before its screen exists,
/// this is what the branch points at for the one commit in between.
class ServiceTabPlaceholder extends ConsumerWidget {
  final ServiceKey service;
  final ServiceTab tab;

  const ServiceTabPlaceholder({
    super.key,
    required this.service,
    required this.tab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(service)) {
      // `.forService`, never the generic form: it names the service and its
      // door goes to that service's own connection form rather than to the
      // settings index.
      return NotConfiguredPlaceholder.forService(service);
    }

    // `AppEmptyStatePage`, not a bare `AppEmptyState`: a leaf that cannot
    // scroll clips its own second line at an accessibility reading size, and
    // this copy is two lines at every size.
    return AppEmptyStatePage(
      emptyState: AppEmptyState(
        icon: Icons.hourglass_empty_rounded,
        title: '${tab.label} is not here yet',
        message:
            'Cupola does not read ${service.title}’s '
            '${tab.label.toLowerCase()} yet. Everything else on this service '
            'works.',
        accentColor: service.accent,
      ),
    );
  }
}
