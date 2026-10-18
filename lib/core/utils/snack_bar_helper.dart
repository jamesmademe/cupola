import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';

/// Convenience helpers for showing semantically typed snackbars.
///
/// The app theme already configures shared snackbar styling in `core/theme.dart`.
/// These helpers keep call sites small and centralize semantic variants.
///
/// Usage:
/// ```dart
/// SnackBarHelper.success(context, 'Settings saved');
/// SnackBarHelper.info(context, 'Coming soon!');
/// SnackBarHelper.error(context, "Could not delete this movie from Radarr.", detail: e);
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
  /// The diagnostic never replaces the sentence: a raw `DioException` is not
  /// an explanation, and it is dropped entirely when it is empty, so the
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
  /// whose target is not configured prints *"Set up qBittorrent to open this
  /// transfer."* with **Set up qBittorrent**; a write blocked by a read-only credential
  /// prints what the key cannot do with **Update the key**.
  ///
  /// It is a toast and not a dialog because nothing was destroyed and nothing
  /// needs confirming: the user tapped a control that cannot act, and the
  /// answer is an explanation plus a door. A dialog would make them dismiss it.
  ///
  /// Nothing in the app could express this before: every `SnackBar` raised here
  /// was content-only, so a control that refused to act could say *what*
  /// happened and never *what to do about it*, which is the half that matters.
  ///
  /// Default styling on purpose: this is not an error, and the error variant's
  /// toned glyph would make a configuration fact look like a fault.
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

  /// Shows a failure snackbar: the toast's own plate, with the failure's
  /// glyph in the failure's tone ahead of the words.
  ///
  /// Pass the caught object as [detail] rather than interpolating it into
  /// [message]: `'Search failed: $e'` puts a stack-trace fragment where a
  /// sentence belongs, while `error(context, "Could not start a search in
  /// Radarr.", detail: e)` leads with what the user needs and demotes the
  /// diagnostic to its own line: the same two-register shape `AppErrorState`
  /// uses.
  ///
  /// Pass it as [cause] instead when [message] already says why in the
  /// classification's words (`writeFailureReason`, `sectionFailureMessage`):
  /// the glyph takes its tone from it and nothing is printed twice.
  ///
  /// [duration] is for the rare failure that needs longer than the default four
  /// seconds: a grab that failed after the sheet moved on, say, where the user
  /// has to read a sentence they did not expect. Everything else takes the
  /// default; a snackbar that lingers is one the user has to dismiss.
  ///
  /// [onRetry] puts `Retry` on the toast, sends the same request again, and is
  /// drawn only where the classified cause can clear ([failureRetryHelps]): a
  /// key the service refused is refused again, and a Retry that cannot help
  /// is a promise the app cannot keep.
  ///
  /// ## The tone is on the glyph
  ///
  /// The brand book's Presence Rule: a fault is a quiet line, and its tone
  /// lives on the glyph, never on a fill behind it. The plate is the one every
  /// toast sits on (`inverse-surface`), and the glyph ([failureIcon] of the
  /// classified [cause] or [detail]) is red only when nothing answered; amber
  /// for every fault: a refused key, a 5xx, a write the service turned down:
  /// and for a toast that carries no cause at all, a form that cannot be saved
  /// or a link nothing can open, because "did not answer" is a claim about a
  /// host and nothing here supports it. The plate used to be `colorScheme.error`
  /// for all of them, so a key Radarr had just refused read exactly like a
  /// switched-off box, in a red fill.
  static void error(
    BuildContext context,
    String message, {
    Object? detail,
    Object? cause,
    Duration? duration,
    VoidCallback? onRetry,
  }) {
    final theme = Theme.of(context);
    final reason = classifyConnectionFailure(cause ?? detail);
    final messenger = ScaffoldMessenger.of(context);
    final retry = onRetry != null && failureRetryHelps(reason) ? onRetry : null;
    // Walked against the plate it sits on, which is dark in both rooms: the
    // day room's red and amber are drawn for paper and would sink into it.
    final glyph = statusToneColor(
      theme.colorScheme,
      failureTone(reason),
      surface:
          theme.snackBarTheme.backgroundColor ??
          theme.colorScheme.inverseSurface,
    );
    messenger.showSnackBar(
      SnackBar(
        duration: duration ?? const Duration(seconds: 4),
        action: retry == null
            ? null
            : SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  retry();
                },
              ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The words carry the state; the glyph is its tone, not a second
            // announcement.
            ExcludeSemantics(
              child: Icon(failureIcon(reason), size: 18, color: glyph),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(_compose(message, detail))),
          ],
        ),
      ),
    );
  }
}
