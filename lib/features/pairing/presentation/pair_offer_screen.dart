import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/qr_code_view.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/presentation/pair_words.dart';
import 'package:cupola/features/settings/presentation/widgets/invite_sheet.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_steps.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';

/// Settings › Set up another device: a code another device points its camera
/// at (or pastes the link of) to copy everything this one has, once, over the
/// home network.
///
/// The operator's only: the requester has no connection to hand over. The
/// page makes the code on its first frame and **closes it when it goes**
/// ([pairOfferProvider] is autoDispose, and closing its server is what
/// disposing it does), so a code never outlives the screen that shows it.
///
/// The code holds no secret: where to fetch the package and the key that
/// opens it, for the two minutes the server stays up. Everything else is
/// said on the page: what moves, what stays behind, and why it is safe.
class PairOfferScreen extends ConsumerStatefulWidget {
  const PairOfferScreen({super.key});

  /// The code's tile, and the place that holds it in every state, so nothing
  /// below it moves when the code arrives.
  static const qrSide = InviteSheet.qrSide;

  /// How long the button says *Link copied* before it offers the copy again.
  static const copiedFor = InviteSheet.copiedFor;

  /// The widest the page's column grows on a window.
  static const columnWidth = 560.0;

  @override
  ConsumerState<PairOfferScreen> createState() => _PairOfferScreenState();
}

class _PairOfferScreenState extends ConsumerState<PairOfferScreen> {
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _start() => ref
      .read(pairOfferProvider.notifier)
      .start(
        from: PairDevice.of(
          defaultTargetPlatform,
          tablet: MediaQuery.sizeOf(context).shortestSide >= 600,
        ),
      );

  Future<void> _copy(PairLink link) async {
    await Clipboard.setData(ClipboardData(text: link.toLink()));
    if (!mounted) return;
    setState(() => _copied = true);
    // The label changes under a focused button, which a screen reader does
    // not read by itself.
    announce(context, 'Link copied');
    _copiedTimer?.cancel();
    _copiedTimer = Timer(PairOfferScreen.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _done() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(ServiceRoutes.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairOfferProvider);
    final theme = Theme.of(context);
    return AmbientScaffold(
      // No accent: a settings pane has no artwork, so its room is lit by the
      // neutral lamp, the fallback of `AmbientBackground`.
      appBar: const GlassAppBar(title: Text('Set up another device')),
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: PairOfferScreen.columnWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'On the other phone, open Cupola and choose Copy from '
                      'another device.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    ..._body(context, state),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, PairOfferState state) {
    return switch (state) {
      PairOfferPreparing() => [
        const _CodeSlot(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
      PairOfferOpen(:final link, :final package) => _open(
        context,
        link,
        package,
      ),
      PairOfferSent() => _sent(context),
      PairOfferClosed(:final how) => _closed(context, how),
      PairOfferNoNetwork() => [
        NoticeLine(
          tone: StatusTone.info,
          title: 'Join your Wi-Fi to make a code',
          sentence:
              'The other phone fetches everything over your home network.',
          actions: [noticeAction(context, Lexicon.retry, _start)],
        ),
      ],
      PairOfferFailed() => [
        NoticeLine(
          tone: StatusTone.warning,
          title: "Cupola could not open the code",
          sentence: 'Wait a moment, then make a new code.',
          actions: [
            noticeAction(
              context,
              'Make a new code',
              _start,
              fill: StatusTone.warning,
            ),
          ],
        ),
      ],
    };
  }

  List<Widget> _open(BuildContext context, PairLink link, PairPackage package) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall!.copyWith(
      color: CupolaThemeColors.of(context).dimText,
    );
    final network = ref.read(pairNetworkProvider);
    return [
      Center(
        child: QrCodeView(
          data: link.toLink(),
          size: PairOfferScreen.qrSide,
          semanticLabel: 'QR code to copy from this device',
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Scan with the camera on the other phone',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.xs),
      _Countdown(closesAt: link.closesAt, now: network.now, style: dim),
      const SizedBox(height: AppSpacing.sm),
      // The way to a Mac, which has no camera: the link, as a message.
      Center(
        child: TextButton.icon(
          onPressed: () => _copy(link),
          style: retryInkStyle(theme.colorScheme),
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.link_rounded,
            size: 18,
          ),
          label: Text(_copied ? 'Link copied' : 'Copy link'),
        ),
      ),
      if (defaultTargetPlatform == TargetPlatform.macOS) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'If your Mac asks, allow Cupola to accept incoming connections.',
          textAlign: TextAlign.center,
          style: dim,
        ),
      ],
      const SizedBox(height: AppSpacing.xl),
      const SettingsSectionLabel('What moves'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          for (final move in pairMovesOf(package))
            SettingsCard.grouped(
              leading: Icon(move.icon),
              title: move.title,
              subtitle: move.detail,
              // A sentence, not a label: it wraps, where a row's subtitle
              // would be cut to one line.
              subtitleMaxLines: 4,
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
      const SettingsSectionLabel("Why it's safe"),
      const SizedBox(height: AppSpacing.sm),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Text(
          'The code holds no secrets: only where to fetch them and the key to '
          'open them. It works once.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Center(
        child: TextButton(
          onPressed: ref.read(pairOfferProvider.notifier).close,
          style: retryInkStyle(theme.colorScheme),
          child: const Text('Close the code now'),
        ),
      ),
    ];
  }

  List<Widget> _sent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      _CodeSlot(
        child: Icon(
          Icons.check_rounded,
          size: 72,
          color: statusToneColor(
            colorScheme,
            StatusTone.success,
            surface: colorScheme.surfaceContainer,
          ),
        ),
      ),
      ..._result(
        context,
        'Copied to the other phone',
        'It has everything now. The code is closed.',
        SeerrSignInPrimary(label: 'Done', onPressed: _done),
      ),
    ];
  }

  List<Widget> _closed(BuildContext context, PairServerEnd how) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      _CodeSlot(
        child: Icon(
          Icons.qr_code_2_rounded,
          size: 72,
          color: statusToneColor(
            colorScheme,
            StatusTone.neutral,
            surface: colorScheme.surfaceContainer,
          ),
        ),
      ),
      ..._result(
        context,
        'The code closed',
        pairClosedBecause(how),
        SeerrSignInPrimary(label: 'Make a new code', onPressed: _start),
      ),
    ];
  }

  /// What the code's place says once it is not a code: a line, why, and the
  /// one button.
  List<Widget> _result(
    BuildContext context,
    String title,
    String why,
    Widget primary,
  ) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: AppSpacing.lg),
      Semantics(
        container: true,
        liveRegion: true,
        label: '$title. $why',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium!.weight(FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                why,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: CupolaThemeColors.of(context).dimText,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      primary,
    ];
  }
}

/// The code's place when there is no code: the same square, so the page does
/// not jump when the code arrives or leaves.
class _CodeSlot extends StatelessWidget {
  const _CodeSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox.square(
        dimension: PairOfferScreen.qrSide,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// `Closes in 1:52`, ticking each second to the code's end. Not a live
/// region: a reader walking the page hears the time it is on, and the end
/// says nothing new, because the page changes by itself.
class _Countdown extends StatefulWidget {
  const _Countdown({
    required this.closesAt,
    required this.now,
    required this.style,
  });

  final DateTime closesAt;
  final DateTime Function() now;
  final TextStyle style;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: false,
    child: Text(
      pairCountdown(widget.closesAt.difference(widget.now())),
      textAlign: TextAlign.center,
      style: widget.style,
    ),
  );
}
