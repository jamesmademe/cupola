import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_glyph_row.dart';
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

/// Whether this window puts the ring beside the step instead of above it.
///
/// Platform first, then shape. The width test this replaced asked for
/// `AppBreakpoints.desktopCompact` (1100), which is why the four drawn compact
/// onboarding frames were code the app could not reach: at 720 the flow kept
/// the phone's stacked arrangement in a window shaped nothing like a phone.
///
/// The threshold itself now lives on [AppBreakpoints] as `landscapeAspect`,
/// beside `touchRail` and `desktopCompact`, which is where the constant said it
/// belonged while it sat here: it is a size class, not a fact about onboarding.
/// This function keeps only the half that *is* about onboarding — the platform
/// gate in front of it.
bool onboardingSideBySide(BuildContext context) {
  if (!AppBreakpoints.isDesktopShell(context)) return false;
  return AppBreakpoints.isLandscapeFrame(context);
}

/// The well on a desktop window, where the ring sits *beside* the step.
///
/// 1040 rather than the well every other screen uses: the ring is 396 and the
/// form wants its own 560, and those two plus the air between them is what this
/// number is. It is not a reading measure — nothing here is prose.
const onboardingDesktopMaxWidth = 1040.0;

/// The ring at the size DESIGN.md protects it at.
///
/// On a phone the diameter is negotiated against whatever height the keyboard
/// leaves; in a wide window there is nothing to negotiate with, so it is a
/// constant and the instrument stops resizing under the user mid-flow.
const onboardingDesktopRingDiameter = 396.0;

/// The same instrument in a compact window, where the whole frame is 450pt tall.
///
/// 230, which is what the compact board draws, rather than the 286 the full
/// constant resolves to once the column's own reservation is taken off: a ring
/// that fills nine tenths of a short window is not the subject of the beat, it
/// is the beat.
const onboardingCompactRingDiameter = 230.0;

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

/// The instrument's slot, in either of the two registers the flow gives it.
///
/// The ring is the flow's landmark and it earns its size — but only while there
/// is a screen to put it on. It sat above an `Expanded`, so it did not shrink to
/// make room: with the keyboard up it squeezed the form into a ~60pt slot,
/// clipping the address field mid-glyph and hiding the validation message that
/// explains why the step will not advance. Sizing it from the height actually
/// left over fixed the clipping — and on every phone traded it for a ring that
/// was simply gone, because a software keyboard leaves roughly 420pt of column
/// and the beat's own content wants more than that on its own.
///
/// So scarcity changes the instrument's *register* rather than removing it. The
/// full register is the hero above the beat. The compact one moves it beside
/// [label] — the step's eyebrow, which is the orientation the full subject line
/// was carrying — into a single header row that costs about what the subject
/// line alone used to. That is where the ~100pt the form needs comes from, and
/// the ring stays on screen while the user types.
///
/// It is the *same* ring in both: the row is the same shape at either end of the
/// animation, so the element — and with it every transition the ring is holding
/// mid-flight — survives the change. Only its size, the label's width and the
/// gutters interpolate. The node radii do not: they are absolute (4–6pt), which
/// is why a 96pt ring still reads as fifteen distinct services rather than as a
/// smudge.
///
/// [collapsed] is the last resort, for a screen so short that even the compact
/// register would eat the form's floor. Nothing is lost when it fires:
/// [OnboardingWalkSubject] is back at full height by then and still names the
/// service and the step.
///
/// Both are decided by the screen, the only place that knows the height
/// available and what the beat below needs — see
/// `_OnboardingScreenState._fullRingDiameter` and its compact counterpart.
class OnboardingInstrument extends StatelessWidget {
  const OnboardingInstrument({
    super.key,
    required this.collapsed,
    required this.compact,
    this.label,
    required this.child,
  });

  /// Whether there is no longer enough height to show a legible ring at all.
  final bool collapsed;

  /// Whether the instrument is in its compact register, beside [label] rather
  /// than above the whole beat.
  final bool compact;

  /// The step's eyebrow, shown only in the compact register. Null on the beats
  /// that have no subject of their own — the door, the choice and the close.
  final Widget? label;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Reduce Motion removes the animator rather than shortening it, which for
    // this slot is the difference between a ring that jumps register and one
    // that visibly scales and cross-fades every time the keyboard opens — the
    // most-repeated tween in the whole flow and the one a motion-sensitive user
    // meets on every step.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _slot(context, collapsed ? 0 : 1);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
      builder: (context, t, _) => _slot(context, t),
    );
  }

  /// The slot at [t], where 0 is fully given back and 1 is fully open.
  Widget _slot(BuildContext context, double t) {
    // Gone means gone: at zero the slot contributes no height, no semantics
    // and no paint, so the form's Expanded gets the full remainder.
    return t == 0
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
                  child: _register(context),
                ),
              ),
            ),
          );
  }

  Widget _register(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _row(context, compact ? 1 : 0);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: compact ? 1 : 0),
      duration: AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
      builder: (context, c, _) => _row(context, c),
    );
  }

  /// The header row at [c], where 0 is the full register and 1 the compact one.
  Widget _row(BuildContext context, double c) => Padding(
    // The full register's gutters are for a hero with a beat under it. The
    // compact one is a header strip, and every point it keeps is a point the
    // focused field does not get.
    padding: EdgeInsets.only(
      top: _lerp(AppSpacing.lg, AppSpacing.sm, c),
      bottom: _lerp(AppSpacing.md, AppSpacing.sm, c),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        child,
        // Built only while it contributes something. A zero-width, fully
        // transparent slot still occupies the tree, and this label is the same
        // sentence [OnboardingWalkSubject] is showing in the full register —
        // so leaving it mounted put the step's eyebrow in the semantics tree
        // twice, which a screen reader reads out as two steps.
        if (label case final label? when c > 0)
          // Loose by default, so the moment it goes the ring is centred by the
          // row exactly as it was before the label existed.
          Flexible(
            child: ClipRect(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                // Widens out from behind the ring rather than fading in
                // place — the label is arriving from where it used to be.
                widthFactor: c,
                child: Opacity(
                  // Trails the width so the two eyebrows — this one and the
                  // subject line's, which is collapsing on the same clock —
                  // are never both legible at once.
                  opacity: Curves.easeIn.transform(
                    ((c - 0.4) / 0.6).clamp(0.0, 1.0),
                  ),
                  child: ExcludeSemantics(
                    // Mid-flight the subject line is still on its way out, so
                    // for those few frames neither speaks. One of the two is
                    // always the settled answer.
                    excluding: c < 1,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppSpacing.lg,
                        end: AppSpacing.md,
                      ),
                      child: label,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// A slot that gives its height back when the beat stops needing what is in it.
///
/// The counterpart to [OnboardingInstrument]'s compact register: the step's full
/// subject line folds away exactly as the instrument takes its eyebrow over, so
/// the two read as one label moving rather than as two labels, one of which
/// disappeared.
class OnboardingCollapsible extends StatelessWidget {
  const OnboardingCollapsible({
    super.key,
    required this.collapsed,
    required this.child,
  });

  final bool collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The instrument's own gate, on the same clock and for the same reason: the
    // two halves of this handover have to agree about whether there is a
    // handover to watch.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _fold(collapsed ? 0 : 1, child);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
      builder: (context, t, content) => _fold(t, content!),
      child: child,
    );
  }

  Widget _fold(double t, Widget content) => t == 0
      ? const SizedBox.shrink()
      : ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            // Leaves ahead of the fold, for the same reason the ring does.
            child: Opacity(
              opacity: Curves.easeOut.transform(t),
              // Hands the spoken label over cleanly: on its way out this is no
              // longer the step's voice, and the instrument's own label has not
              // finished arriving. See [OnboardingInstrument].
              child: ExcludeSemantics(excluding: t < 1, child: content),
            ),
          ),
        );
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
    //
    // The field's own focus, as the walk's other dismissals do. Unfocusing
    // the route's whole scope took the focus out of the page, and on a phone
    // a tap on the field then left the keyboard down (11/10).
    onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
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
    this.besideRing = MainAxisAlignment.center,
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

  /// The same choice beside the ring, where [alignment]'s phone reasoning has
  /// nothing to hold on to.
  ///
  /// `center` by default: with no ring above and no thumb below, the step
  /// centres on the instrument it is paired with. `start` only for the walk,
  /// whose subject line is hoisted above the pager — centring the form under it
  /// would open a hole between the sentence and the field it introduces.
  final MainAxisAlignment besideRing;

  @override
  Widget build(BuildContext context) {
    if (onboardingSideBySide(context)) return _besideRing(context);
    return Padding(
      // The generous top and bottom gutters are for a beat sitting against the
      // screen edge. With the keyboard up there is no edge below — the key rows
      // are the edge — and that spare 44pt is exactly what the pinned actions
      // need in order not to overflow once the dismiss bar takes its place.
      padding: OnboardingKeyboardScope.of(context)
          ? onboardingPadding.copyWith(
              top: AppSpacing.md,
              bottom: AppSpacing.sm,
            )
          : onboardingPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                // Dragging the form puts the keyboard away, the platform gesture
                // for exactly that.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    // `end` means "sit under the ring, close to the thumb" — a
                    // phone answer to a phone layout.
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

  /// The window arrangement: copy and actions as one group, centred on the ring.
  ///
  /// Pinned to the foot of the column the actions sat a hand's width below the
  /// sentence that argues for them, with nothing in between — the right answer
  /// on a phone, where the foot of the screen is where the thumb already is, and
  /// the wrong one in a window. Riding inside the scrollable instead is what
  /// clipped the primary action on the 720x450 board, where notes on services
  /// such as Readarr and TrueNAS pushed it below the window.
  ///
  /// A loose [Flexible] answers both. While the copy fits it takes only its own
  /// height, so copy and actions travel together and the group centres; once it
  /// does not, the copy is capped at what is left and scrolls, and the actions
  /// stay on screen under it.
  Widget _besideRing(BuildContext context) {
    return Padding(
      padding: onboardingPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: besideRing,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
          if (actions != null) ...[
            const SizedBox(height: AppSpacing.xl),
            actions!,
          ],
        ],
      ),
    );
  }
}

/// Two actions side by side, stacking once the reading size stops letting them
/// share a line. Past roughly 1.4x the labels overlap rather than elide.
///
/// Full width on a phone, where the pair spans the thumb's reach. Beside the
/// ring the buttons keep their own width instead: stretched across a 600pt
/// column, "Continue" became a banner rather than a button, and the eye had to
/// travel the whole bar to find its label.
class OnboardingFooter extends StatelessWidget {
  const OnboardingFooter({super.key, this.secondary, required this.primary});

  final Widget? secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    final sideBySide = onboardingSideBySide(context);
    if (secondary == null) {
      return sideBySide
          ? primary
          : SizedBox(width: double.infinity, child: primary);
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
      mainAxisSize: sideBySide ? MainAxisSize.min : MainAxisSize.max,
      children: [
        secondary!,
        const SizedBox(width: AppSpacing.md),
        // Loose, not tight: the primary keeps its own width while the pair
        // fits, and still yields to the column on the 720x450 board, where a
        // long service name next to "Test connection" does not.
        if (sideBySide) Flexible(child: primary) else Expanded(child: primary),
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
      // Through the footer, not a hand-rolled Column. The door was the one beat
      // that stacked its pair unconditionally — a full-width primary over a
      // text button — so it kept a composition the other three give up as soon
      // as the reading size allows a row, and it would not have inherited the
      // footer's stacking rule if that rule ever changed.
      actions: OnboardingFooter(
        secondary: TextButton(
          onPressed: onSkip,
          child: const Text('Skip for now'),
        ),
        primary: FilledButton(
          onPressed: onStart,
          child: const Text('Set up my stack'),
        ),
      ),
      children: [
        const OnePunchline(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${ServiceKey.values.length} self-hosted services: media, downloads '
          'and storage, all on one screen, talking straight to your own '
          'boxes. No cloud in the middle.',
          style: theme.textTheme.bodyLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A headline with the one word the claim leans on, set like [OnePunchline]'s
/// "Cupola" and "your lab.".
///
/// In the headline's own ink: the room is monochrome (the brand book's principle 3), so the
/// word is carried by the display face and its place in the line, never by a
/// hue — a section's cyan here was decoration, and it measured 2.2:1 on paper
/// before it was walked.
class _AccentedHeadline extends StatelessWidget {
  const _AccentedHeadline({
    required this.before,
    required this.accent,
    required this.after,
    required this.style,
  });

  final String before;
  final String accent;
  final String after;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(text: accent),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      style: style,
    );
  }
}

// ── Beat 2: the pick ────────────────────────────────────────────────────────

/// Every service as a chip in four labelled sectors, and the ring above as a
/// live readout of the choice.
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
      children: [
        // Plain, and deliberately so: the leaning headline is the door's and
        // the close's device, and this beat's own voice is its seventeen chips
        // and the lit nodes above them.
        Text(
          'Pick your services',
          style: theme.textTheme.headlineMedium!.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Pick what you actually run. Nothing here is permanent. Services '
          'can be added or dropped any time in Settings.',
          style: theme.textTheme.bodyMedium!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final domain in ServiceDomain.values) ...[
          Text(
            domain.label,
            style: AppTheme.chrome(
              context,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
    // The brand book's selected chip: the ink fill with the on-ink label, the same for every
    // service — the chip names the service in words, and a hue per chip turned
    // the beat into a seventeen-colour legend with nothing to decode.
    final labelColor = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    // 44pt is the iOS minimum target; the label grows the box past it.
    const constraints = BoxConstraints(minHeight: 44);
    const padding = EdgeInsets.symmetric(horizontal: AppSpacing.md);
    final decoration = BoxDecoration(
      color: selected ? scheme.primary : scheme.surfaceContainer,
      borderRadius: AppRadius.borderRadiusMd,
      border: Border.all(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
    );
    // Seventeen of these, and picking a stack means tapping most of them — so
    // under Reduce Motion the animator goes entirely rather than running short:
    // this is the beat's most-repeated movement, and the chip's state is
    // already legible from its fill and its lit node.
    final still = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: service.title,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: AppRadius.borderRadiusMd,
          child: still
              ? Container(
                  constraints: constraints,
                  padding: padding,
                  decoration: decoration,
                  child: _label(theme, labelColor),
                )
              : AnimatedContainer(
                  duration: AppAnimation.durationSm,
                  curve: AppAnimation.emphasizedCurve,
                  constraints: constraints,
                  padding: padding,
                  decoration: decoration,
                  child: _label(theme, labelColor),
                ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, Color labelColor) {
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? scheme.onPrimary
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

  /// The service the close offers as the example of what can still be added.
  ///
  /// Lidarr by preference, and explicitly **not** Readarr: Readarr is retired
  /// upstream, so naming it as the thing to add later is advice with a dead end.
  /// When Lidarr is itself already in the stack the example falls to the first
  /// registry service that is not — offering to add something the user set up
  /// two minutes ago is the same defect wearing different clothes. Null when
  /// there is genuinely nothing left, which is the one case the sentence has to
  /// drop the name rather than pick a wrong one.
  ServiceKey? get _exampleToAdd {
    final missing = ServiceKey.values
        .where(
          (s) =>
              s != ServiceKey.readarr &&
              !connected.contains(s) &&
              !silent.contains(s),
        )
        .toList(growable: false);
    if (missing.isEmpty) return null;
    return missing.contains(ServiceKey.lidarr)
        ? ServiceKey.lidarr
        : missing.first;
  }

  String get _body {
    if (connected.isEmpty && silent.isEmpty) {
      // Dashboard, not Services: the home is `/dashboard` and the cards the
      // sentence points at are the ones on it.
      return 'Cupola will stay empty until you add a service. You can do '
          'that any time in Settings, or from any dark card on the Dashboard.';
    }
    if (silent.isEmpty) {
      // The count first, then the reassurance, then the honest sentence. The
      // reassurance used to sit in the headline's neighbourhood with nothing
      // behind it: a user who connected three of seventeen was told their
      // whole stack was in one place, which is the sort of claim that teaches
      // someone not to read the next one.
      final example = _exampleToAdd;
      final rest = example == null
          ? 'Anything you add later goes in Settings, or on any dark card on '
                'the Dashboard.'
          : '${example.title} and the rest can be added any time in Settings, '
                'or from any dark card on the Dashboard.';
      return '${connected.length}/${ServiceKey.values.length} services '
          'answered. Everything you set up is ready to use. $rest';
    }
    final names = silent.map((s) => s.title).join(', ');
    final verb = silent.length == 1 ? 'is' : 'are';
    return '$names $verb configured but nothing came back. Cupola will keep '
        'trying, or you can look at it now.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headlineStyle = theme.textTheme.displaySmall!.copyWith(
      color: scheme.onSurface,
    );
    return OnboardingBeat(
      alignment: MainAxisAlignment.end,
      actions: OnboardingFooter(
        secondary: silent.isEmpty
            ? OutlinedButton(onPressed: onReview, child: const Text('Review'))
            : OutlinedButton(
                onPressed: () => onFix(silent.first),
                child: Text('Fix ${silent.first.title}'),
              ),
        primary: _FinishButton(onFinish: onFinish),
      ),
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
          Text('Nothing set up yet.', style: headlineStyle)
        else
          _AccentedHeadline(
            before: 'Nothing left in the ',
            accent: 'dark',
            after: '.',
            style: headlineStyle,
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _body,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        // The ring resolved into a result. It is the services that *answered*
        // and not the ones that were picked: a lit tile for a service that
        // never replied would be the close contradicting its own headline, and
        // the mixed-outcome arm already names those in the body.
        if (connected.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          OnboardingGlyphRow(services: connected),
        ],
      ],
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
    this.breadcrumb,
    this.help,
    this.trailing,
    this.warningFor,
    this.focusNode,
    this.action,
    this.onSubmitted,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final bool isUrl;
  final bool isSecret;
  final String? hint;

  /// Owned by the step, not by the field, because the return key's job is to
  /// hand focus to the *next* field and only the step knows what that is.
  final FocusNode? focusNode;

  /// What the return key says. Defaults to the shape of a lone field — `next`
  /// for an address, `done` otherwise — which is only right when nothing wires
  /// [onSubmitted].
  final TextInputAction? action;

  /// Runs on the return key. Wired explicitly rather than left to the
  /// framework's default for [TextInputAction.next], which moves focus to the
  /// next *traversable* widget — here the reveal toggle or the port chip sitting
  /// inside the same field, not the field below it.
  final ValueChanged<String>? onSubmitted;

  /// Where the value is to be found in the service's own UI — `Radarr →
  /// Settings → General → API Key`.
  ///
  /// It sits on the **label row**, beside the label, rather than under the
  /// field, and that is the whole point of it being a separate parameter from
  /// [help]: the slot under a field belongs to what the field has to say about
  /// what was typed. Sharing one slot meant a Plex token warning erased the
  /// path to the token, and a mistyped address erased the port hint — the two
  /// pieces of guidance a user needs *while* they fix it.
  final String? breadcrumb;

  /// A steady line under the field — what the default port is, what happens if
  /// both credentials are left blank. Not a validation result, and no longer
  /// replaced by one: a validation message renders in addition to it.
  final String? help;

  final Widget? trailing;

  /// A live, non-blocking check on the typed value.
  final String? Function(String value)? warningFor;

  /// A blocking check, run when the `Form` around the field validates: its
  /// message takes the note slot under the field, in the error tone, as an
  /// address that cannot be sent does.
  final FormFieldValidator<String>? validator;

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
    // A `user:password@` is accepted: the test takes it off the address and
    // puts it where the connection form does (the Access row's password, or
    // the service's own sign-in).
    final error = raw.trim().isEmpty
        ? null
        : UrlUtils.validateServiceHost(raw, allowCredentials: true);
    // The service's own reason about the scheme wins over the general one: a
    // TrueNAS address over http:// is refused, not merely risky.
    final warning = error == null
        ? (widget.warningFor?.call(raw) ?? UrlUtils.cleartextWarning(raw))
        : null;
    if (error == _error && warning == _warning) return;
    setState(() {
      _error = error;
      _warning = warning;
    });
  }

  @override
  Widget build(BuildContext context) {
    final validator = widget.validator;
    if (validator == null) return _build(context, _error);
    return FormField<String>(
      validator: (_) => validator(widget.controller.text),
      builder: (field) => _build(context, field.errorText ?? _error),
    );
  }

  Widget _build(BuildContext context, String? error) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = error ?? _warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // Baselines, not boxes: the breadcrumb is smaller than the label and
          // the two have to sit on one line of type rather than on one box.
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              widget.label,
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            if (widget.breadcrumb case final breadcrumb?) ...[
              const SizedBox(width: AppSpacing.md),
              // Flexible and wrapping rather than elided: the path is the whole
              // value of the line, and `Settings → General → API…` sends the
              // user looking for a menu that does not exist.
              Flexible(
                child: Text(
                  breadcrumb,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
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
            border: error == null
                ? null
                : Border.all(color: scheme.error.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: widget.label,
                  hint: widget.isUrl
                      ? 'Enter the ${widget.label.toLowerCase()}'
                      : (widget.hint ?? 'Enter ${widget.label.toLowerCase()}'),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    onSubmitted: widget.onSubmitted,
                    obscureText: widget.isSecret && !_revealed,
                    keyboardType: widget.isUrl
                        ? TextInputType.url
                        : TextInputType.text,
                    textInputAction:
                        widget.action ??
                        (widget.isUrl
                            ? TextInputAction.next
                            : TextInputAction.done),
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
                      // Every state is borderless and unfilled: the container
                      // draws the frame and the well, and the app-wide fill and
                      // focused border would paint a second box inside this one.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
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
        // Both, never one instead of the other. The validation message comes
        // first because it is about what is in the field right now; the steady
        // note keeps its place under it, so fixing an address does not cost the
        // user the sentence that says which port to put there.
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              note,
              style: theme.textTheme.bodySmall!.copyWith(
                // Error and warning are the two tones a field can carry: red
                // is "this cannot be sent", amber is "this will work and is
                // worth knowing about". Through `statusToneColor` rather than
                // the raw token, which measures 1.39:1 on paper — the note it
                // paints is the one the user is meant to read before typing
                // anything else.
                color: statusToneColor(
                  scheme,
                  error != null ? StatusTone.error : StatusTone.warning,
                ),
              ),
            ),
          ),
        if (widget.help case final help?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              help,
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
