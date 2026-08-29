import 'package:flutter/widgets.dart';

/// How a widget on the Portal's floor says "the user acted on me".
///
/// The Portal already closes when the content under its card moves — that hook
/// lives in `ShellScreen` and is *reactive*, which is exactly right for what it
/// watches. It cannot, however, answer for an action that moves nothing: a
/// picker cell for the connection the lens is already pointing at, tapped from
/// the page that cell leads to, navigates to the path it is already on and
/// leaves the lens where it was. Neither of the hook's two inputs changes, so
/// the Portal stayed open over its own snapshot and the tap read as inert.
///
/// An act on the Portal closes the Portal, whatever happens underneath, and
/// that belongs at the site of the act. This scope is the wire: the floor
/// installs it, and anything the floor renders can dismiss the layer it is
/// standing on without knowing what that layer is or owning a reference to it.
///
/// A callback rather than the controller itself, deliberately. The matrix is a
/// `/services` widget that the Portal happens to reuse as its floor; handing it
/// `ServicePortalController` would make the dashboard's own instrument depend
/// on the shell's animation machine, and would close an import cycle between
/// the two features besides.
class PortalDismissScope extends InheritedWidget {
  const PortalDismissScope({
    super.key,
    required this.onDismiss,
    required super.child,
  });

  /// Called when a descendant performs the action it exists for.
  final VoidCallback onDismiss;

  /// The dismisser above [context], or null when this widget is not on a
  /// dismissable layer — which is the ordinary case: the same matrix renders on
  /// the `/services` dashboard, where there is nothing to close.
  static VoidCallback? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PortalDismissScope>()
      ?.onDismiss;

  @override
  bool updateShouldNotify(PortalDismissScope oldWidget) =>
      oldWidget.onDismiss != onDismiss;
}
