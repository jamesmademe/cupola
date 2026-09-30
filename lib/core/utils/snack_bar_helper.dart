import 'package:flutter/material.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/service_theme.dart';

/// Convenience helpers for showing semantically typed snackbars.
///
/// The app theme already configures shared snackbar styling in `core/theme.dart`.
/// These helpers keep call sites small and centralize semantic variants.
///
/// Usage:
/// ```dart
/// SnackBarHelper.success(context, 'Settings saved');
/// SnackBarHelper.info(context, 'Coming soon!');
/// SnackBarHelper.error(context, "Couldn't delete this movie from Radarr.", detail: e);
/// ```
class SnackBarHelper {
  SnackBarHelper._();

  /// Strips the `Exception: ` prefix Dart's own `toString()` adds and trims,
  /// so a thrown `Exception('404 Not Found')` demotes to `404 Not Found`
  /// rather than shouting its own type at the user.
  ///
  /// A transport failure is never stringified. A `DioException`'s
  /// `toString()` is a class name and a library's paragraph ("This indicates
  /// an error which most likely cannot be solved by the library"), and it was
  /// the second line of every write toast in the app. It demotes to what the
  /// service itself said, when it said something (`failureServiceMessage`),
  /// and otherwise to the classification's plain sentence.
  ///
  /// Returns `null` when nothing legible survives, which is the signal to show
  /// the human sentence alone rather than a blank second line.
  static String? _demote(Object? detail) {
    if (detail == null) return null;
    if (isTransportFailure(detail)) return failureDiagnostic(detail);
    final text = detail
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// Composes a human sentence with an optional demoted diagnostic line.
  ///
  /// One message, two registers: the first line says what failed in words the
  /// user can act on, the second carries whatever the service actually said.
  /// The diagnostic never replaces the sentence — a raw `DioException` is not
  /// an explanation — and it is dropped entirely when it is empty, so the
  /// snackbar never grows a blank row.
  static String _compose(String message, Object? detail) {
    final demoted = _demote(detail);
    return demoted == null ? message : '$message\n$demoted';
  }

  /// Shows an informational snackbar with the default themed appearance.
  static void info(BuildContext context, String message, {Object? detail}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_compose(message, detail))));
  }

  /// Shows a success snackbar using the default themed appearance.
  static void success(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Shows a message whose one action is the fix for what it just said.
  ///
  /// The shape the design settles on for every "you cannot do that here yet"
  /// answer: four seconds, one sentence, **one** action, and the action
  /// resolves the sentence rather than acknowledging it. A cross-service jump
  /// whose target is not configured prints *"Connect qBittorrent to open this
  /// transfer"* with **Settings**; a write blocked by a read-only credential
  /// prints what the key cannot do with **Update the key**.
  ///
  /// It is a toast and not a dialog because nothing was destroyed and nothing
  /// needs confirming — the user tapped a control that cannot act, and the
  /// answer is an explanation plus a door. A dialog would make them dismiss it.
  ///
  /// Nothing in the app could express this before: every `SnackBar` raised here
  /// was content-only, so a control that refused to act could say *what*
  /// happened and never *what to do about it*, which is the half that matters.
  ///
  /// Default styling on purpose — this is not an error, and the error variant's
  /// red-backgrounded plate would make a configuration fact look like a fault.
  static void withAction(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        content: Text(message),
        action: SnackBarAction(
          label: actionLabel,
          onPressed: () {
            // The bar is dismissed first so the destination is not pushed under
            // a floating toast that then hangs over it for the rest of its four
            // seconds.
            messenger.hideCurrentSnackBar();
            onAction();
          },
        ),
      ),
    );
  }

  /// Shows an error snackbar with the theme error background color.
  ///
  /// Pass the caught object as [detail] rather than interpolating it into
  /// [message]: `'Search failed: $e'` puts a stack-trace fragment where a
  /// sentence belongs, while `error(context, "Couldn't start a search in
  /// Radarr.", detail: e)` leads with what the user needs and demotes the
  /// diagnostic to its own line — the same two-register shape `AppErrorState`
  /// uses.
  /// [duration] is for the rare failure that needs longer than the default four
  /// seconds — a grab that failed after the sheet moved on, say, where the user
  /// has to read a sentence they did not expect. Everything else takes the
  /// default; a snackbar that lingers is one the user has to dismiss.
  static void error(
    BuildContext context,
    String message, {
    Object? detail,
    Duration? duration,
  }) {
    final background = Theme.of(context).colorScheme.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: duration ?? const Duration(seconds: 4),
        // The theme's snackbar ink is chosen for `inverseSurface`, and this is
        // the one snackbar that repaints its own background — so it has to pick
        // its own foreground too. DESIGN.md's Luminance Rule: an opaque accent
        // resolves its ink through `foregroundOn`, never by assuming white.
        // Assuming it here measured 3.5:1 on the light theme's error red,
        // against a 4.5:1 floor; resolved, it lands on the dark ink at 5.2:1.
        // Set on the `Text` because `SnackBar` takes its content style from the
        // theme; a `Text` style merges over that and changes only the colour.
        content: Text(
          _compose(message, detail),
          style: TextStyle(color: ServiceTheme.foregroundOn(background)),
        ),
        backgroundColor: background,
      ),
    );
  }
}
