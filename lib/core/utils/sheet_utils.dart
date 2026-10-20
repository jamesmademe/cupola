import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';

/// Utilities for showing modal bottom sheets that work correctly with the
/// floating navigation bar.
///
/// Problem: Bottom sheets shown within the shell's Navigator are covered by
/// the 80dp floating nav bar because the shell uses `extendBody: true`.
///
/// Solution: This helper uses `useRootNavigator: true` to show sheets above
/// the nav bar at a higher z-index, ensuring they are not obscured.
///
/// Where there is room ([AppBreakpoints.sheetsAreDialogs]: 720 wide, a tablet
/// as a desktop) a sheet does not rise from the bottom: it is the theme's
/// dialog, centred, [dialogWidth] wide ([formWidth] for a form or a picker,
/// [listWidth] for a long list) and up to [heightShare] of the window tall
/// ([tall] holds it there, for a list that scrolls inside). Esc or a click
/// outside closes it. The sheet inside knows it is in one ([SheetInDialog])
/// and draws no handle and no panel of its own.
class SheetUtils {
  SheetUtils._();

  /// A form's or a picker's width: the phone's sheet with room either side.
  static const double formWidth = 520;

  /// A long list's width: a release's name and its figures on one line.
  static const double listWidth = 680;

  /// How much of the window's height a dialog may take.
  static const double heightShare = 0.85;

  /// Shows a modal bottom sheet that appears above the floating nav bar.
  ///
  /// By using `useRootNavigator: true`, the sheet is rendered in the root
  /// navigator context, placing it above the shell's floating nav bar.
  ///
  /// Usage:
  /// ```dart
  /// SheetUtils.showCupolaModalSheet(
  ///   context: context,
  ///   builder: (context) => MyBottomSheet(),
  /// );
  /// ```
  static Future<T?> showCupolaModalSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool enableDrag = true,
    Color? backgroundColor,
    double dialogWidth = formWidth,
    bool tall = false,
  }) {
    if (AppBreakpoints.sheetsAreDialogs(context)) {
      final height = MediaQuery.sizeOf(context).height * heightShare;
      return showDialog<T>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: isDismissible,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: height,
            ),
            child: SizedBox(
              height: tall ? height : null,
              child: SheetInDialog(child: Builder(builder: builder)),
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<T>(
      context: context,
      // Use root navigator to show sheet ABOVE the nav bar (higher z-index)
      useRootNavigator: true,
      // Respect system safe areas (status bar, notches, home indicator)
      useSafeArea: true,
      // Allow sheets to use full screen height if needed
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor,
      builder: builder,
    );
  }
}

/// Marks a sheet shown as a dialog ([SheetUtils.showCupolaModalSheet] where
/// there is room): the sheet draws its header with a close button and its
/// body, and leaves the panel, the handle and the drag to the dialog.
class SheetInDialog extends InheritedWidget {
  const SheetInDialog({super.key, required super.child});

  /// Whether the sheet at [context] is drawn as a dialog.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetInDialog>() != null;

  @override
  bool updateShouldNotify(SheetInDialog oldWidget) => false;
}
