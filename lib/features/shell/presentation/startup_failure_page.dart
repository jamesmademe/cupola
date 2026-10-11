import 'package:flutter/material.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/shell/domain/startup_failure.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

/// The whole app when a start stopped: [StartupFailurePage] in Cupola's two
/// rooms, following the system's, since the person's own choice is in the
/// settings that did not load.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.failure,
    required this.onRetry,
    this.onForgetKeys,
  });

  final StartupFailure failure;

  /// Starts again from the top; see [StartupFailurePage.onRetry].
  final Future<void> Function() onRetry;

  /// See [StartupFailurePage.onForgetKeys].
  final Future<void> Function()? onForgetKeys;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: kAppName,
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    debugShowCheckedModeBanner: false,
    // The same leading as the app's own builder; see `CupolaApp`.
    builder: (context, child) => DefaultTextHeightBehavior(
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      child: child ?? const SizedBox.shrink(),
    ),
    home: StartupFailurePage(
      failure: failure,
      onRetry: onRetry,
      onForgetKeys: onForgetKeys,
    ),
  );
}

/// A start that stopped, said once, with Retry as its one remedy.
///
/// The anatomy of `AppErrorState`'s page form, because it is the same kind of
/// sentence: the glyph and the headline in the fault's amber (something
/// answered wrong, or not in time; nothing is unreachable), the cause one step
/// down and dimmer, Retry in the fault's one amber fill. The platform's own
/// words wait behind Why?, for a bug report, never as the message.
///
/// No service is named, so none of the connection form's remedies apply: what
/// failed is this device's storage, and the only thing to do from here is to
/// ask it again.
class StartupFailurePage extends StatefulWidget {
  const StartupFailurePage({
    super.key,
    required this.failure,
    required this.onRetry,
    this.onForgetKeys,
  });

  final StartupFailure failure;

  /// Runs the start again. On success the app replaces this page; on another
  /// failure a new page replaces it. Retry is held while it runs, so a second
  /// tap does not start a second read of the same storage.
  final Future<void> Function() onRetry;

  /// Empties secure storage and starts again, keeping every address and
  /// preference; offered, after a confirmation, only where the failure says
  /// it is a way on ([StartupFailure.canForget]).
  final Future<void> Function()? onForgetKeys;

  @override
  State<StartupFailurePage> createState() => _StartupFailurePageState();
}

class _StartupFailurePageState extends State<StartupFailurePage> {
  bool _retrying = false;
  bool _whyOpen = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _forget() async {
    final forget = widget.onForgetKeys;
    if (forget == null) return;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Forget the saved keys?',
      message:
          'Addresses, Home and your preferences stay. Each service asks for '
          'its key or password again.',
      confirmLabel: 'Forget keys',
    );
    final confirmed = result.confirmed;
    if (confirmed != true || !mounted) return;
    setState(() => _retrying = true);
    try {
      await forget();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dim = CupolaThemeColors.of(context).dimText;
    final amber = statusToneColor(colorScheme, StatusTone.warning);
    final failure = widget.failure;
    final why = failure.why;

    return Scaffold(
      body: Column(
        children: [
          // The window's drag strip and, off macOS, its buttons: a frameless
          // window with nothing to hold would be one the person cannot move.
          const WindowDragStrip(trail: [kAppName]),
          Expanded(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          failure.step == StartupStep.connections
                              ? Icons.key_off_rounded
                              : Icons.error_outline_rounded,
                          size: 32,
                          color: amber,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Semantics(
                          header: true,
                          child: Text(
                            failure.headline,
                            style: theme.textTheme.titleMedium!
                                .weight(FontWeight.w600)
                                .copyWith(color: amber),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (failure.sentence case final sentence?) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            sentence,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: dim,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        FilledButton.icon(
                          onPressed: _retrying ? null : _retry,
                          style: remedyFillStyle(context),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text(Lexicon.retry),
                        ),
                        if (failure.canForget &&
                            widget.onForgetKeys != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          // Text in ink: the fault has one fill, and it is
                          // on Retry, the step that loses nothing.
                          TextButton(
                            onPressed: _retrying ? null : _forget,
                            child: const Text('Forget saved keys'),
                          ),
                        ],
                        if (why != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _whyOpen = !_whyOpen),
                            iconAlignment: IconAlignment.end,
                            style: TextButton.styleFrom(
                              foregroundColor: dim,
                              minimumSize: const Size(44, 44),
                              visualDensity: VisualDensity.standard,
                            ),
                            icon: Icon(
                              _whyOpen
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'Why?',
                              semanticsLabel: _whyOpen ? 'Hide why' : 'Why?',
                            ),
                          ),
                          if (_whyOpen)
                            SelectableText(
                              why,
                              style: AppType.meta.copyWith(color: dim),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
