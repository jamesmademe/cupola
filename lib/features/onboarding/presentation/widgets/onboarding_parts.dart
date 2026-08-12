import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Screen padding for every beat. Wider than the app's 16dp because a beat is a
/// single centred column with nothing beside it.
const onboardingPadding = EdgeInsets.fromLTRB(
  AppSpacing.xl,
  AppSpacing.xl,
  AppSpacing.xl,
  AppSpacing.xxl,
);

/// Widest the column is allowed to get. Past this a field's label and its
/// control drift too far apart to read as a pair.
const onboardingMaxWidth = 560.0;

/// Whether the keyboard is currently taking screen height, published for the
/// whole flow.
///
/// It has to be *published* rather than read where it is needed. A `Scaffold`
/// with `resizeToAvoidBottomInset` — the default — hands its body a
/// `MediaQuery` with the bottom inset already removed (`scaffold.dart`:
/// `removeViewInsets`), reasoning that it has consumed the keyboard by
/// shrinking the body. So every widget inside the body is told the keyboard is
/// down while it is up. The screen reads the inset outside the `Scaffold` and
/// puts the answer here, where the ring and the beats can both depend on it.
class OnboardingKeyboardScope extends InheritedWidget {
  const OnboardingKeyboardScope({
    super.key,
    required this.up,
    required super.child,
  });

  final bool up;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OnboardingKeyboardScope>()
          ?.up ??
      false;

  @override
  bool updateShouldNotify(OnboardingKeyboardScope oldWidget) =>
      oldWidget.up != up;
}

/// The instrument's slot, which gives its whole height back when the keyboard
/// takes the screen.
///
/// The ring is the flow's landmark and it earns its size — but only while there
/// is a screen to put it on. It sat above an `Expanded`, so it did not shrink to
/// make room: with the keyboard up it squeezed the form into a ~60pt slot,
/// clipping the address field mid-glyph and hiding the validation message that
/// explains why the step will not advance.
///
/// The screen now sizes it from the height actually left over, so it shrinks
/// with the space instead of vanishing at the first sign of a keyboard, and only
/// collapses when what remains is under `serviceRingDiameter`'s own 96pt floor —
/// where a ring is a smudge rather than an instrument.
///
/// Nothing is lost when it does go. [OnboardingWalkSubject] still names the
/// service and the step, which is the orientation the ring was carrying.
///
/// [collapsed] is decided by the screen, which is the only place that knows both
/// the height available and what the beat below needs — see
/// `_OnboardingScreenState._ringDiameter`.
class OnboardingInstrument extends StatelessWidget {
  const OnboardingInstrument({
    super.key,
    required this.collapsed,
    required this.child,
  });

  /// Whether there is no longer enough height to show a legible ring.
  final bool collapsed;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
      // Gone means gone: at zero the slot contributes no height, no semantics
      // and no paint, so the form's Expanded gets the full remainder.
      builder: (context, t, ring) => t == 0
          ? const SizedBox.shrink()
          : ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: t,
                child: Opacity(
                  // Fades out ahead of the collapse so the ring reads as
                  // withdrawing rather than as being cropped by the fold.
                  opacity: Curves.easeOut.transform(t),
                  child: Transform.scale(
                    // Contracts toward its own centre while the slot closes;
                    // scale alone would leave the gap behind, heightFactor alone
                    // would guillotine it.
                    scale: 0.72 + 0.28 * t,
                    child: ring,
                  ),
                ),
              ),
            ),
      child: child,
    );
  }
}

/// The control the keyboard itself does not offer here: a way to put it away.
///
/// iOS gives a URL keyboard no return key that dismisses — the address field
/// asks for `next` because there is a credential field after it, and `done`
/// only appears on the last field of the form. So on the step where the user is
/// most likely to want the screen back, there was no key to press.
///
/// It shares the back row rather than taking a row of its own: a third stacked
/// action cost ~50pt of the height the form was already short of, and the two
/// belong together anyway — both are ways out of the field you are in.
class OnboardingKeyboardDismiss extends StatelessWidget {
  const OnboardingKeyboardDismiss({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    // Names the action rather than saying "Done", which on a form step reads as
    // finishing the step rather than closing the keyboard.
    onPressed: () => FocusScope.of(context).unfocus(),
    icon: const Icon(Icons.keyboard_hide_rounded, size: 18),
    label: const Text('Hide keyboard'),
  );
}

/// A beat whose content is centred while it fits and scrolls once it does not.
///
/// The page owns the viewport, not the content. A ring, a display headline, a
/// paragraph and two buttons fit comfortably at the default reading size and
/// overflow a short phone by four figures at an accessibility one — so the
/// scrollable is the default and the `minHeight` is what keeps the composition
/// centred, rather than the other way round. The actions stay pinned below it,
/// because an action you have to scroll to find is worse than a scroll.
class OnboardingBeat extends StatelessWidget {
  const OnboardingBeat({
    super.key,
    required this.children,
    this.actions,
    this.alignment = MainAxisAlignment.start,
  });

  final List<Widget> children;
  final Widget? actions;

  /// Where the content sits in the space the ring leaves it.
  ///
  /// `start` for the beats that continue straight out of the instrument — a
  /// form or a list reads as attached to it. `end` for the two that are a claim
  /// plus an action, where the copy belongs with the buttons it argues for.
  /// Centring is what both used to do, and with the ring hoisted above the pager
  /// it opened a hole under it on every beat.
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Padding(
    // The generous top and bottom gutters are for a beat sitting against the
    // screen edge. With the keyboard up there is no edge below — the key rows
    // are the edge — and that spare 44pt is exactly what the pinned actions
    // need in order not to overflow once the dismiss bar takes its place.
    padding: OnboardingKeyboardScope.of(context)
        ? onboardingPadding.copyWith(top: AppSpacing.md, bottom: AppSpacing.sm)
        : onboardingPadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // Dragging the form puts the keyboard away, the platform gesture
              // for exactly that.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: alignment,
                  children: children,
                ),
              ),
            ),
          ),
        ),
        if (actions != null) ...[
          const SizedBox(height: AppSpacing.lg),
          actions!,
        ],
      ],
    ),
  );
}

/// Two actions side by side, stacking once the reading size stops letting them
/// share a line. Past roughly 1.4x the labels overlap rather than elide.
class OnboardingFooter extends StatelessWidget {
  const OnboardingFooter({super.key, this.secondary, required this.primary});

  final Widget? secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    if (secondary == null) {
      return SizedBox(width: double.infinity, child: primary);
    }
    if (MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: AppSpacing.sm),
          secondary!,
        ],
      );
    }
    return Row(
      children: [
        secondary!,
        const SizedBox(width: AppSpacing.md),
        Expanded(child: primary),
      ],
    );
  }
}

// ── Beat 1: the door ────────────────────────────────────────────────────────

/// The claim, the ring, and one way in.
class OnboardingDoor extends StatelessWidget {
  const OnboardingDoor({
    super.key,
    required this.onStart,
    required this.onSkip,
  });

  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingBeat(
      alignment: MainAxisAlignment.end,
      children: [
        const OnePunchline(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${ServiceKey.values.length} self-hosted services — media, '
          'downloads, storage — on one screen, talking straight to your own '
          'boxes. No cloud in the middle.',
          style: theme.textTheme.bodyLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      actions: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              child: const Text('Set up my stack'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onSkip, child: const Text('Skip for now')),
        ],
      ),
    );
  }
}

/// One word of a headline in an accent, resolved against the surface it sits
/// on — the same move as [OnePunchline]'s "Cupola" and "your lab.", carried to
/// the two headlines either side of it so the claim's colour vocabulary
/// threads through the whole flow rather than living on the door alone.
class _AccentedHeadline extends StatelessWidget {
  const _AccentedHeadline({
    required this.before,
    required this.accent,
    required this.after,
    required this.accentColor,
    required this.style,
  });

  final String before;
  final String accent;
  final String after;
  final Color accentColor;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = ServiceTheme.onTint(
      accentColor,
      surface: scheme.surface,
      tintAlpha: 0,
    );
    return Text.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: accent,
            style: TextStyle(color: ink),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      style: style,
    );
  }
}

// ── Beat 2: the pick ────────────────────────────────────────────────────────

/// Fifteen services as accent chips in four labelled sectors, and the ring above
/// as a live readout of the choice.
class OnboardingPick extends StatelessWidget {
  const OnboardingPick({
    super.key,
    required this.picked,
    required this.onToggle,
    required this.onContinue,
    required this.onBack,
  });

  final Set<ServiceKey> picked;
  final void Function(ServiceKey) onToggle;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingBeat(
      children: [
        _AccentedHeadline(
          before: '',
          accent: 'Bring',
          after: ' your stack into view.',
          accentColor: AppColors.primary,
          style: theme.textTheme.headlineMedium!
              .weight(FontWeight.w800)
              .copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Pick what you actually run. Nothing here is permanent — services '
          'can be added or dropped any time in Settings.',
          style: theme.textTheme.bodyMedium!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final domain in ServiceDomain.values) ...[
          Text(
            domain.label.toUpperCase(),
            style: AppTheme.eyebrow(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final service in domain.services)
                _PickChip(
                  service: service,
                  selected: picked.contains(service),
                  onTap: () => onToggle(service),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
      actions: OnboardingFooter(
        secondary: OutlinedButton(onPressed: onBack, child: const Text('Back')),
        // The count is the only thing on this beat that reports the choice back,
        // and it changes on every chip tap — so it rolls. The slot is reserved
        // for the longest label the button can ever hold, which is why tapping
        // the fifteenth service moves a digit rather than the whole word.
        primary: ReelCommandButton(
          label: picked.isEmpty ? 'Continue' : 'Continue with ${picked.length}',
          slotLabels: ['Continue with ${ServiceKey.values.length}'],
          onPressed: () async => onContinue(),
        ),
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final ServiceKey service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The chip's own label sits on a tint of the accent, so it resolves through
    // `onTint` — the raw accent fails AA over its own 14% wash in light theme.
    final labelColor = selected
        ? ServiceTheme.onTint(
            service.accent,
            surface: scheme.surface,
            tintAlpha: 0.14,
          )
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: service.title,
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: AppRadius.borderRadiusMd,
        child: AnimatedContainer(
          duration: AppAnimation.durationSm,
          curve: AppAnimation.emphasizedCurve,
          // 44pt is the iOS minimum target; the label grows the box past it.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? service.accent.withValues(alpha: 0.14)
                : scheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(
              color: selected
                  ? service.accent.withValues(alpha: 0.40)
                  : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? service.accent
                      : scheme.onSurfaceVariant.withValues(alpha: 0.40),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Flexible, so a long name at an accessibility reading size wraps
              // onto a second line and the chip grows taller. Unflexed, the
              // Row overflowed the wrap's available width by exactly its own
              // padding — and eliding "qBittor…" is not an option: the name is
              // the only thing the chip says.
              Flexible(
                child: Text(
                  service.title,
                  style: theme.textTheme.titleSmall!
                      .weight(FontWeight.w600)
                      .copyWith(color: labelColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Beat 4: the close ───────────────────────────────────────────────────────

/// What the walk actually achieved, in words, plus a way to fix the one thing
/// that did not answer.
class OnboardingClose extends StatelessWidget {
  const OnboardingClose({
    super.key,
    required this.connected,
    required this.silent,
    required this.onFix,
    required this.onFinish,
    required this.onReview,
  });

  final List<ServiceKey> connected;
  final List<ServiceKey> silent;
  final void Function(ServiceKey) onFix;
  final Future<void> Function() onFinish;
  final VoidCallback onReview;

  /// The mixed outcome as its two painted lines.
  ///
  /// Two strings rather than one with a `\n` because these are the only headline
  /// in the app that **changes while it is being read**: the close mounts and
  /// *then* `_testUntested` checks everything the user never tested by hand, so
  /// the first painted value is "0 answer." and the truth arrives a second later.
  /// That used to be a hard swap — a headline that was briefly, visibly wrong.
  /// Rolled, the close reports as it learns, which is what it was always meant
  /// to do. A rolling line cannot contain a newline, so the split is required as
  /// well as clearer.
  List<String>? get _countLines {
    if (connected.isEmpty && silent.isEmpty) return null;
    if (silent.isEmpty) return null;
    final many = silent.length == 1
        ? "One doesn't."
        : "${silent.length} don't.";
    return ['${connected.length} answer.', many];
  }

  String get _body {
    if (connected.isEmpty && silent.isEmpty) {
      return 'Cupola will stay empty until you add a service — you can do '
          'that any time in Settings, or from any dark card on Services.';
    }
    if (silent.isEmpty) {
      return 'Your whole stack is in one place. Everything you connected is '
          'ready to use.';
    }
    final names = silent.map((s) => s.title).join(', ');
    final verb = silent.length == 1 ? 'is' : 'are';
    return '$names $verb configured but nothing came back. Cupola will keep '
        'trying — or you can look at it now.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headlineStyle = theme.textTheme.displaySmall!
        .weight(FontWeight.w800)
        .copyWith(color: scheme.onSurface);
    return OnboardingBeat(
      alignment: MainAxisAlignment.end,
      children: [
        if (_countLines case final lines?)
          for (final line in lines)
            ReelLine(
              line,
              style: headlineStyle,
              options: ReelMotion.figure,
              // Wrapping is what the plain headline did at accessibility sizes
              // and it stays the fallback, so a reading size that cannot hold
              // "12 don't." on one line loses the roll rather than the line.
              fallbackMaxLines: null,
            )
        else if (connected.isEmpty && silent.isEmpty)
          Text('Nothing connected yet.', style: headlineStyle)
        else
          _AccentedHeadline(
            before: 'Nothing left in the ',
            accent: 'dark',
            after: '.',
            accentColor: AppColors.navActivity,
            style: headlineStyle,
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _body,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      actions: OnboardingFooter(
        secondary: silent.isEmpty
            ? OutlinedButton(onPressed: onReview, child: const Text('Review'))
            : OutlinedButton(
                onPressed: () => onFix(silent.first),
                child: Text('Fix ${silent.first.title}'),
              ),
        primary: _FinishButton(onFinish: onFinish),
      ),
    );
  }
}

class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.onFinish});
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) => ReelCommandButton(
    label: 'Enter Cupola',
    busyLabel: 'Opening',
    onPressed: onFinish,
  );
}

// ── Fields ──────────────────────────────────────────────────────────────────

/// One labelled field, with the live checks that keep a typo from being reported
/// as a network fault.
class OnboardingField extends StatefulWidget {
  const OnboardingField({
    super.key,
    required this.label,
    required this.controller,
    this.isUrl = false,
    this.isSecret = false,
    this.hint,
    this.help,
    this.trailing,
    this.warningFor,
  });

  final String label;
  final TextEditingController controller;
  final bool isUrl;
  final bool isSecret;
  final String? hint;

  /// A steady line under the field — where the credential lives, what the
  /// default port is. Not a validation result.
  final String? help;

  final Widget? trailing;

  /// A live, non-blocking check on the typed value.
  final String? Function(String value)? warningFor;

  @override
  State<OnboardingField> createState() => _OnboardingFieldState();
}

class _OnboardingFieldState extends State<OnboardingField> {
  String? _error;
  String? _warning;

  /// Secrets start hidden but must be checkable: a 32-character key typed on a
  /// phone keyboard is unverifiable behind dots.
  bool _revealed = false;

  bool get _watches => widget.isUrl || widget.warningFor != null;

  @override
  void initState() {
    super.initState();
    if (_watches) {
      widget.controller.addListener(_validate);
      _validate();
    }
  }

  @override
  void dispose() {
    if (_watches) widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _validate() {
    final raw = widget.controller.text;
    if (!widget.isUrl) {
      final custom = raw.trim().isEmpty ? null : widget.warningFor?.call(raw);
      if (custom == _warning && _error == null) return;
      setState(() {
        _error = null;
        _warning = custom;
      });
      return;
    }
    // An untouched field is not scolded. A cleartext address outside the local
    // network is a warning rather than an error: it is a supported choice, just
    // one worth naming — along with the routes that avoid it.
    final error = raw.trim().isEmpty ? null : UrlUtils.validateServiceHost(raw);
    final warning = error == null ? _addressWarning(raw) : null;
    if (error == _error && warning == _warning) return;
    setState(() {
      _error = error;
      _warning = warning;
    });
  }

  /// Extends `cleartextWarning`'s remedy from "use https" to the three routes
  /// this audience actually uses.
  static String? _addressWarning(String raw) {
    if (UrlUtils.cleartextWarning(raw) == null) return null;
    return 'This address is off your local network and http:// sends your '
        'credentials in the clear. Reach it over a reverse proxy with TLS, a '
        'VPN like Tailscale, or a Cloudflare Tunnel instead.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = _error ?? _warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.labelMedium!
              .weight(FontWeight.w600)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: AppRadius.borderRadiusMd,
            border: _error == null
                ? null
                : Border.all(color: scheme.error.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  obscureText: widget.isSecret && !_revealed,
                  keyboardType: widget.isUrl
                      ? TextInputType.url
                      : TextInputType.text,
                  textInputAction: widget.isUrl
                      ? TextInputAction.next
                      : TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  // Smart substitutions off as well as autocorrect: iOS
                  // otherwise rewrites `--` and quotes inside a typed address.
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    // https by default: the clients normalise a scheme-less
                    // host to TLS, and an http:// placeholder taught the
                    // opposite.
                    hintText: widget.isUrl
                        ? 'https://your-server:port'
                        : widget.hint,
                    hintStyle: theme.textTheme.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    isDense: true,
                    // Every state is borderless: the container draws the frame,
                    // and the app-wide focused border would paint a second box
                    // inside this one.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (widget.isSecret)
                Semantics(
                  button: true,
                  label: _revealed
                      ? 'Hide ${widget.label}'
                      : 'Show ${widget.label}',
                  child: IconButton(
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: _revealed
                        ? 'Hide ${widget.label}'
                        : 'Show ${widget.label}',
                  ),
                ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              note,
              style: theme.textTheme.bodySmall!.copyWith(
                color: _error != null ? scheme.error : AppColors.warning,
              ),
            ),
          )
        else if (widget.help != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              widget.help!,
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
