import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/home/presentation/widgets/stack_health_module.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The Home, set up three ways: it draws what its services can feed, leaves
/// out a module with no source, and one module says what to set up next.
void main() {
  const phone = Size(390, 2400);

  testWidgets('first day, Radarr, Sonarr and Seerr: nothing of a media '
      'server, and Set up next names it once', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      child: const HomeScreen(),
      surfaceSize: phone,
    );
    expect(find.text('Continue watching'), findsNothing);
    expect(find.text('Now playing'), findsNothing);
    expect(find.text('Set up next'), findsOne);
    expect(find.text('Set up Jellyfin'), findsOne);
    expect(find.text('Set up a download client'), findsOne);
    expect(find.text('Set up Seerr'), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('no Seerr: Requests is left out, and Seerr is what to set up '
      'next', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p4,
      child: const HomeScreen(),
      surfaceSize: phone,
    );
    expect(find.text('Requests'), findsNothing);
    expect(find.text('Set up Seerr'), findsOne);
    expect(find.text('Set up a download client'), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('the full household with Stack health and Storage switched '
      'on: every light, and the pools', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const HomeScreen(),
      overrides: [homeLayoutProvider.overrideWith(_WithLights.new)],
      // Tall enough for the whole Home: a list builds only what it shows.
      surfaceSize: const Size(390, 6000),
    );
    expect(find.text('Stack'), findsOne);
    // Eleven services: the two Radarrs fold into one light.
    expect(find.byType(StackLightMark), findsNWidgets(11));
    expect(find.text('fast'), findsOne);
    expect(find.text('72%'), findsOne);
    await harness.unmount(tester);
  });
}

class _WithLights extends HomeLayoutNotifier {
  @override
  HomeLayout build() => HomeLayout.defaultFor(Audience.operator)
      .switched(HomeModule.stackHealth, on: true)
      .switched(HomeModule.storage, on: true);
}
