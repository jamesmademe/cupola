import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';

/// One group of rows on a Media page or one of its sheets: the room's quiet
/// fill, `AppRadius.group`, a hairline round it and between the rows.
class MediaGroup extends StatelessWidget {
  const MediaGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.slabY),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.group),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) Divider(height: 1, color: room.hair),
            child,
          ],
        ],
      ),
    );
  }
}

/// The style of the one action that leads a Media page, and of the action
/// that closes one of its sheets: lit by the title, the tinted fill under its
/// ink in the dark room and the tinted primary under white in the day room.
/// Unlit, the ink.
ButtonStyle mediaLeadStyle(BuildContext context, TitleLight? light) {
  final base = AppTheme.primaryButtonStyle(context);
  if (light == null) return base;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final ink = dark ? light.actionInk : const Color(0xFFFFFFFF);
  return base.copyWith(
    backgroundColor: WidgetStatePropertyAll(
      dark ? light.actionFill : light.dayPrimary,
    ),
    foregroundColor: WidgetStatePropertyAll(ink),
    iconColor: WidgetStatePropertyAll(ink),
  );
}
