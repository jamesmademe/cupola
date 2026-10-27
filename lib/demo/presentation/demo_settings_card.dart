import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/demo/demo_door.dart';
import 'package:cupola/demo/demo_session.dart';

/// The first thing in Settings while the demo runs: where the visitor is,
/// and the way out. Nothing outside the demo.
///
/// Leaving asks nothing: nothing real is lost, and the app starts again on
/// the onboarding it left.
class DemoSettingsCard extends ConsumerWidget {
  const DemoSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoRunningProvider)) return const SizedBox.shrink();
    final door = ref.watch(demoDoorProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroupCard(
          children: [
            const SettingsCard.grouped(
              leading: Icon(Icons.cottage_outlined),
              title: "You're exploring a demo home",
              subtitle:
                  'Its servers are made up, and nothing you do here is kept.',
              subtitleMaxLines: 4,
            ),
            SettingsCard.grouped(
              leading: const Icon(Icons.logout_rounded),
              title: 'Leave demo',
              subtitle: 'Back to the start, to set up your own',
              subtitleMaxLines: 2,
              semanticHint: 'ends the demo and opens the welcome',
              onTap: door?.leave,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
