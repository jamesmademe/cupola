import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The one-line answer to "is my stack all right", derived once.
///
/// Every desktop surface that prints an aggregate — the deck's compact readout,
/// the status bar, the services alert band's own headline — reads this, so the
/// three of them cannot disagree about how many services are answering. Three
/// widgets each counting for themselves is how a window ends up saying `14 of
/// 16` in one corner and `2 unreachable` next to `all clear` in another.
@immutable
class StackHealth {
  const StackHealth({
    required this.configured,
    required this.answering,
    required this.unreachable,
    required this.checking,
    required this.notSetUp,
  });

  /// Services with at least one connection set up. The denominator.
  final int configured;

  /// Configured services that answered.
  final int answering;

  /// Configured services that were asked and said no.
  final int unreachable;

  /// Configured services still being asked. Not a fault, and never counted as
  /// one — this is what stops the readout crying wolf for the first second of
  /// every cold open.
  final int checking;

  /// Services in the registry nobody has set up. Also not a fault: a stack
  /// without Readarr is not a stack missing Readarr.
  final int notSetUp;

  bool get allClear => unreachable == 0;

  /// `14 of 16 answering`, or `16 of 16 answering` when nothing is wrong.
  String get headline => '$answering of $configured answering';

  /// The qualifiers that follow the headline, already in reading order and
  /// omitted when they are zero.
  List<String> get qualifiers => [
    if (unreachable > 0) '$unreachable unreachable',
    if (checking > 0) '$checking checking',
    if (notSetUp > 0) '$notSetUp not set up',
  ];

  /// The whole line, spoken and printed the same way.
  String get sentence => [headline, ...qualifiers].join(' · ');
}

/// The live aggregate. Rebuilds when any service's reachability moves.
final stackHealthProvider = Provider<StackHealth>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  final configured = ServiceKey.values
      .where(settings.isServiceConfigured)
      .toList(growable: false);

  var answering = 0;
  var unreachable = 0;
  var checking = 0;
  for (final service in configured) {
    final summary = ref.watch(serviceSummaryProvider(service)).asData?.value;
    if (summary == null) {
      checking++;
    } else if (summary.isOnline) {
      answering++;
    } else {
      unreachable++;
    }
  }

  return StackHealth(
    configured: configured.length,
    answering: answering,
    unreachable: unreachable,
    checking: checking,
    notSetUp: ServiceKey.values.length - configured.length,
  );
});
