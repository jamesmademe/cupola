import 'package:flutter/material.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/demo/presentation/demo_mark.dart';

/// A tab's name at the top of its page (the Home's day, Discover, Activity,
/// Requests, Stack), in the screen role, followed by the demo's mark while
/// the demo runs ([DemoMark]).
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Semantics(
            header: true,
            child: Text(text, style: AppType.screen.copyWith(color: room.ink)),
          ),
        ),
        const DemoMark(),
      ],
    );
  }
}
