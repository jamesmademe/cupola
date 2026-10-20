import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';

/// One thing a row offers beside opening it: `Delete request`.
typedef RowAction = ({String label, IconData icon, VoidCallback onSelected});

/// The menu of [actions] under [at] (the row's own corner when the press
/// left no point), the theme's menu as every ⋯ draws it.
Future<void> showRowActions(
  BuildContext context,
  Offset? at,
  List<RowAction> actions,
) async {
  if (actions.isEmpty) return;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final row = context.findRenderObject() as RenderBox?;
  final point =
      at ?? row?.localToGlobal(row.size.centerLeft(Offset.zero)) ?? Offset.zero;
  final local = overlay.globalToLocal(point);
  final chosen = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      local & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final (index, action) in actions.indexed)
        PopupMenuItem(
          value: index,
          child: Row(
            children: [
              Icon(action.icon, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(action.label)),
            ],
          ),
        ),
    ],
  );
  if (chosen != null) actions[chosen].onSelected();
}
