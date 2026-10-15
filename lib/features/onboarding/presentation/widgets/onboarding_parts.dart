import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/widgets/setup_doors.dart';
import 'package:cupola/core/widgets/status_badge.dart';
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
/// This function keeps only the half that *is* about onboarding: the platform
/// gate in front of it.
bool onboardingSideBySide(BuildContext context) {
  if (!AppBreakpoints.isDesktopShell(context)) return false;
  return AppBreakpoints.isLandscapeFrame(context);
}

/// The well on a desktop window, where the ring sits *beside* the step.
///
/// 1040 rather than the well every other screen uses: the ring is 396 and the
/// form wants its own 560, and those two plus the air between them is what this
/// number is. It is not a reading measure; nothing here is prose.
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
/// with `resizeToAvoidBottomInset` (the default) hands its body a
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
/// The ring is the flow's landmark and it earns its size, but only while there
/// is a screen to put it on. It sat above an `Expanded`, so it did not shrink to
/// make room: with the keyboard up it squeezed the form into a ~60pt slot,
/// clipping the address field mid-glyph and hiding the validation message that
/// explains why the step will not advance. Sizing it from the height actually
/// left over fixed the clipping, and on every phone traded it for a ring that
/// was simply gone, because a software keyboard leaves roughly 420pt of column
/// and the beat's own content wants more than that on its own.
///
/// So scarcity changes the instrument's *register* rather than removing it. The
/// full register is the hero above the beat. The compact one moves it beside
/// [label]: the step's eyebrow, which is the orientation the full subject line
/// was carrying, into a single header row that costs about what the subject
/// line alone used to. That is where the ~100pt the form needs comes from, and
/// the ring stays on screen while the user types.
///
/// It is the *same* ring in both: the row is the same shape at either end of the
/// animation, so the element, and with it every transition the ring is holding
/// mid-flight, survives the change. Only its size, the label's width and the
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
/// available and what the beat below needs: see
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
  /// that have no subject of their own: the door, the choice and the close.
  final Widget? label;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Reduce Motion removes the animator rather than shortening it, which for
    // this slot is the difference between a ring that jumps register and one
    // that visibly scales and cross-fades every time the keyboard opens: the
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
        // sentence [OnboardingWalkSubject] is showing in the full register,
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
                // place: the label is arriving from where it used to be.
                widthFactor: c,
                child: Opacity(
                  // Trails the width so the two eyebrows, this one and the
                  // subject line's, which is collapsing on the same clock,
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
/// iOS gives a URL keyboard no return key that dismisses: the address field
/// asks for `next` because there is a credential field after it, and `done`
/// only appears on the last field of the form. So on the step where the user is
/// most likely to want the screen back, there was no key to press.
///
/// It shares the back row rather than taking a row of its own: a third stacked
/// action cost ~50pt of the height the form was already short of, and the two
/// belong together anyway; both are ways out of the field you are in.
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
/// overflow a short phone by four figures at an accessibility one, so the
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
    this.controller,
    this.subjectAbove = false,
  });

  final List<Widget> children;
  final Widget? actions;

  /// The content's scroll, for the one beat whose owner puts it back at the
  /// top: Connect, which Found's Back returns to as it was left.
  final ScrollController? controller;

  /// Whether a subject is hoisted right above the beat, as Connect's is.
  ///
  /// The subject keeps its own gap under it, so the top gutter would double it:
  /// 40pt between "Start with another service" and the form's first label, and
  /// a two-field form 30pt taller than a 6.3" phone has for it at rest, so the
  /// first field scrolled out of view as soon as the second took the cursor
  /// (13/10).
  final bool subjectAbove;

  /// Where the content sits in the space the ring leaves it.
  ///
  /// `start` for the beats that continue straight out of the instrument: a
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
  /// whose subject line is hoisted above the pager: centring the form under it
  /// would open a hole between the sentence and the field it introduces.
  final MainAxisAlignment besideRing;

  @override
  Widget build(BuildContext context) {
    if (onboardingSideBySide(context)) return _besideRing(context);
    return Padding(
      // The generous top and bottom gutters are for a beat sitting against the
      // screen edge. With the keyboard up there is no edge below: the key rows
      // are the edge, and that spare 44pt is exactly what the pinned actions
      // need in order not to overflow once the dismiss bar takes its place.
      padding: OnboardingKeyboardScope.of(context)
          ? onboardingPadding.copyWith(
              top: AppSpacing.md,
              bottom: AppSpacing.sm,
            )
          : onboardingPadding.copyWith(top: subjectAbove ? 0 : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                controller: controller,
                // Dragging the form puts the keyboard away, the platform gesture
                // for exactly that.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    // `end` means "sit under the ring, close to the thumb": a
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
  /// sentence that argues for them, with nothing in between: the right answer
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
              controller: controller,
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

// ── The Welcome ─────────────────────────────────────────────────────────────

/// The claim and the way in: what a first run opens on.
///
/// There is no way past it. With nothing set up the shell has nothing to show,
/// and the Home at zero would only say the same thing again inside the tabs.
class OnboardingWelcome extends StatelessWidget {
  const OnboardingWelcome({super.key, required this.onSetUp, this.onBack});

  /// Opens Connect, with Seerr proposed.
  final VoidCallback onSetUp;

  /// Back where the visit came from, for a Welcome opened from inside the app
  /// ("Revisit onboarding"). Null on a first run, which came from nowhere.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingBeat(
      alignment: MainAxisAlignment.end,
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SetupDoors(onSetUp: onSetUp),
          if (onBack case final back?) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: back, child: const Text('Back')),
          ],
        ],
      ),
      children: [
        const OnePunchline(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Cupola talks straight to the services you run at home. No Cupola '
          'account, no cloud in between.',
          style: theme.textTheme.bodyLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── The close ───────────────────────────────────────────────────────────────

/// The end of the way in: what answered, under the ring lit with it, and the
/// one way on, into the app.
///
/// The headline is Cupola's promise, [OnePunchline.closing], and it is earned:
/// it is said only when everything this visit tried has joined. When something
/// did not (a found service that did not answer, or whose key never came), the
/// headline counts instead and the body names what is missing: a promise said
/// over a gap is the sort of claim that teaches someone not to read the next
/// one.
class OnboardingClose extends StatelessWidget {
  const OnboardingClose({
    super.key,
    required this.answering,
    this.notJoined = const [],
    required this.setUp,
    required this.onEnter,
  });

  /// What this visit set up and heard back from, by name, in the order set up.
  final List<String> answering;

  /// What the visit tried, or was told about, and could not add, by name.
  final List<String> notJoined;

  /// Every service with a connection now, so the example of what to add next
  /// is never one already there.
  final Set<ServiceKey> setUp;

  final Future<void> Function() onEnter;

  /// Names as a sentence says them: "Seerr", "Seerr and Radarr", "Seerr,
  /// Radarr and Sonarr", and past three the first two "and 3 more".
  static String sayNames(List<String> names) => switch (names) {
    [final one] => one,
    [final a, final b] => '$a and $b',
    [final a, final b, final c] => '$a, $b and $c',
    [final a, final b, ...final rest] => '$a, $b and ${rest.length} more',
    _ => '',
  };

  /// The service offered as the example of what can still be added: Lidarr by
  /// preference, and never Readarr, which is retired upstream, so naming it as
  /// the thing to add next is advice with a dead end. Null when everything
  /// else is already there.
  ServiceKey? get _exampleToAdd {
    final missing = [
      for (final s in ServiceKey.values)
        if (s != ServiceKey.readarr && !setUp.contains(s)) s,
    ];
    if (missing.isEmpty) return null;
    return missing.contains(ServiceKey.lidarr)
        ? ServiceKey.lidarr
        : missing.first;
  }

  String get _body {
    final heard =
        '${sayNames(answering)} ${answering.length == 1 ? 'is' : 'are'} '
        'answering.';
    if (notJoined.isNotEmpty) {
      final one = notJoined.length == 1;
      return '$heard ${sayNames(notJoined)} ${one ? 'is' : 'are'} not added '
          'yet: add ${one ? 'it' : 'them'} any time from Connections in '
          'Settings.';
    }
    final example = _exampleToAdd;
    if (example == null) return heard;
    return '$heard ${example.title} and the rest can be added any time from '
        'Connections in Settings.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tried = answering.length + notJoined.length;
    return OnboardingBeat(
      alignment: MainAxisAlignment.end,
      actions: OnboardingFooter(
        primary: ReelCommandButton(
          label: 'Enter Cupola',
          busyLabel: 'Opening',
          onPressed: onEnter,
        ),
      ),
      children: [
        if (notJoined.isEmpty)
          const OnePunchline.closing()
        else
          Semantics(
            header: true,
            child: Text(
              '${answering.length} of $tried answering.',
              style: theme.textTheme.displayMedium!.copyWith(
                color: scheme.onSurface,
                height: 1.10,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _body,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Start with another service ──────────────────────────────────────────────

/// Every service by what it is for, with the two that know the others first:
/// where Connect goes when the person would rather not start with Seerr.
///
/// A list to choose one from, not a set to tick: each service is set up on its
/// own, and the ones Seerr or Prowlarr know follow from them.
class OnboardingStart extends StatelessWidget {
  const OnboardingStart({
    super.key,
    required this.onPick,
    required this.onBack,
  });

  final ValueChanged<ServiceKey> onPick;
  final VoidCallback onBack;

  static const _knowTheOthers = [ServiceKey.seerr, ServiceKey.prowlarr];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = CupolaThemeColors.of(context).dimText;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(text, style: AppTheme.chrome(context, color: dim)),
      ),
    );
    Widget row(ServiceKey service, {required bool named}) {
      final title = named ? service.title : 'Set up ${service.title}';
      final subtitle = service.knowsOthers ?? service.role;
      return SettingsCard.grouped(
        leading: Icon(service.icon),
        title: title,
        subtitle: subtitle,
        subtitleMaxLines: 3,
        trailing: const Icon(Icons.chevron_right_rounded),
        semanticLabel: '$title. $subtitle',
        semanticHint: 'opens its address and key',
        onTap: () => onPick(service),
      );
    }

    return OnboardingBeat(
      actions: TextButton(onPressed: onBack, child: const Text('Back')),
      children: [
        Semantics(
          header: true,
          child: Text(
            'Start with another service',
            style: theme.textTheme.headlineMedium!.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Two services already know most of your stack. Any other one is set '
          'up on its own.',
          style: theme.textTheme.bodyMedium!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        label('They know the others'),
        SettingsGroupCard(
          children: [
            for (final service in _knowTheOthers) row(service, named: true),
          ],
        ),
        for (final domain in ServiceDomain.values) ...[
          label(domain.label),
          SettingsGroupCard(
            children: [
              for (final service in domain.services)
                if (!_knowTheOthers.contains(service))
                  row(service, named: false),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Each one asks for its address and key, and is saved only once it '
          'answers.',
          style: theme.textTheme.bodySmall!.copyWith(color: dim),
        ),
      ],
    );
  }
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
    this.problem,
  });

  final String label;
  final TextEditingController controller;
  final bool isUrl;
  final bool isSecret;
  final String? hint;

  /// Owned by the step, not by the field, because the return key's job is to
  /// hand focus to the *next* field and only the step knows what that is.
  final FocusNode? focusNode;

  /// What the return key says. Defaults to the shape of a lone field: `next`
  /// for an address, `done` otherwise, which is only right when nothing wires
  /// [onSubmitted].
  final TextInputAction? action;

  /// Runs on the return key. Wired explicitly rather than left to the
  /// framework's default for [TextInputAction.next], which moves focus to the
  /// next *traversable* widget: here the reveal toggle or the port chip sitting
  /// inside the same field, not the field below it.
  final ValueChanged<String>? onSubmitted;

  /// Where the value is to be found in the service's own UI: `Radarr →
  /// Settings → General → API Key`.
  ///
  /// It sits on the **label row**, beside the label, rather than under the
  /// field, and that is the whole point of it being a separate parameter from
  /// [help]: the slot under a field belongs to what the field has to say about
  /// what was typed. Sharing one slot meant a Plex token warning erased the
  /// path to the token, and a mistyped address erased the port hint: the two
  /// pieces of guidance a user needs *while* they fix it.
  final String? breadcrumb;

  /// A steady line under the field: what the default port is, what happens if
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

  /// What a press found wrong with the field, said in the error tone until
  /// the caller clears it on the next edit: an empty address, or one the
  /// press refused. Before what the field finds as it is typed.
  final String? problem;

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
    // one worth naming, along with the routes that avoid it.
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
    if (validator == null) return _build(context, widget.problem ?? _error);
    return FormField<String>(
      validator: (_) => validator(widget.controller.text),
      builder: (field) =>
          _build(context, field.errorText ?? widget.problem ?? _error),
    );
  }

  Widget _build(BuildContext context, String? error) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = error ?? _warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, row) => Row(
            // Baselines, not boxes: the breadcrumb is smaller than the label
            // and the two have to sit on one line of type rather than on one
            // box.
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // The label takes what it needs, up to half the row beside a
              // breadcrumb: a label that names a connection (`Radarr 4K's API
              // key`) wraps there at a large reading size instead of
              // overflowing. Two Flexibles split the row in halves instead,
              // and Seerr's path broke onto a second line beside a label a
              // third its width (13/10).
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.breadcrumb == null
                      ? row.maxWidth
                      : row.maxWidth / 2,
                ),
                child: Text(
                  widget.label,
                  style: theme.textTheme.labelMedium!
                      .weight(FontWeight.w600)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (widget.breadcrumb case final breadcrumb?) ...[
                const SizedBox(width: AppSpacing.md),
                // Wrapping rather than elided: the path is the whole value of
                // the line, and `Settings → General → API…` sends the user
                // looking for a menu that does not exist.
                Expanded(
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
                          ? widget.hint ?? 'https://your-server:port'
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
                // the raw token, which measures 1.39:1 on paper. The note it
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
