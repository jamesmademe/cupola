import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/tag_chip.dart';
import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';

/// The demo's mark after a tab's name: a neutral `Demo`, so nobody takes the
/// world's servers for their own. Nothing outside the demo.
///
/// A tap opens Settings, whose first row says where the visitor is and holds
/// `Leave demo`.
class DemoMark extends ConsumerWidget {
  const DemoMark({super.key});

  /// What the mark says to a screen reader, beside its label.
  static const hint = 'Opens Settings, where you can leave the demo.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoRunningProvider)) return const SizedBox.shrink();
    void open() => openSettings(context, ref);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      // One button, said once: the chip's own text is left out.
      child: Semantics(
        button: true,
        label: 'Demo home',
        hint: hint,
        onTap: open,
        excludeSemantics: true,
        child: InkResponse(
          onTap: open,
          radius: 28,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: const Center(child: TagChip(text: 'Demo')),
          ),
        ),
      ),
    );
  }
}
