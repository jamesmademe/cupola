import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/core/widgets/app_card.dart';

/// Settings' way to Edit Home: `Home`, and how it is arranged.
class SettingsHomeRow extends ConsumerWidget {
  const SettingsHomeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    return SettingsCard.grouped(
      leading: const Icon(Icons.home_outlined),
      title: 'Home',
      subtitle: layout.summary,
      semanticHint: 'opens Edit Home',
      onTap: () => context.push(ServiceRoutes.settingsHome),
    );
  }
}
