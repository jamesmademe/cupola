import 'package:flutter/material.dart';
import 'package:reel_text/reel_text.dart';

import 'package:cupola/core/app_animation.dart';

/// The app's roll vocabulary: four presets, and no call site may hand-write a
/// `ReelTextOptions`.
///
/// `reel_text` ships its own defaults — a 300ms roll on `Cubic(0.34, 1.56, 0.64,
/// 1)` with `bounce: 0.6` — and they are a springy overshoot chosen to look good
/// in a package demo. Nothing in this app moves on that curve. Durations and
/// curves come from [AppAnimation], so they come from here too, and the presets
/// below are the only place the two systems meet.
///
/// **Stagger has no [AppAnimation] equivalent**, because nothing else in the app
/// staggers *within* a single string — [StaggeredEntrance] staggers between
/// siblings at 45ms and that is a different axis. The values below are
/// authored, and each one is a ratio of the roll it belongs to rather than a
/// number picked by eye: a figure's glyphs travel almost together (the value is
/// one unit), a state word's a little wider (a word is read as a word), a
/// command's tight under the thumb.
///
/// See also the Reduce Motion note on [waiting] — the one preset that is not
/// self-suppressing.
abstract final class ReelMotion {
  ReelMotion._();

  /// A live number updating in place: a transfer rate, a queue count, a KPI.
  ///
  /// The quietest preset in the set, because it is the one that fires without
  /// being asked. A figure re-rolls on every poll on screens the user watches
  /// for minutes, so it gets no overshoot (`bounce: 0`), the app's own
  /// state-change duration, and a stagger tight enough that a four-digit value
  /// reads as one object dropping into place rather than four digits arriving in
  /// sequence.
  ///
  /// It also carries **no colour flash**. `ReelTextOptions.color` tints incoming
  /// glyphs before fading back, and spending that on a status figure would make
  /// hue carry health — which is the thing the Room Light Rule exists to
  /// prevent. A figure changes brightness and position, never hue.
  static const figure = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 18),
    exitOffset: Duration(milliseconds: 28),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0,
  );

  /// A state word changing because the thing it describes changed:
  /// `Queued` → `Downloading` → `Importing`.
  ///
  /// Same clock as [figure] and a slightly wider stagger. A word is read as a
  /// word, so its letters may arrive across a short sweep — but only just: past
  /// about 24ms per glyph a nine-letter state word takes longer to settle than
  /// the poll interval that produced it, and the label is then permanently in
  /// motion.
  static const word = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 22),
    exitOffset: Duration(milliseconds: 34),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0,
  );

  /// A command label answering a press: `Test connection` → `Next service`.
  ///
  /// The one preset that keeps a trace of overshoot, and it is earned rather
  /// than decorative — this roll is *feedback for a touch*, the same job
  /// [PressableScale]'s 0.97 dip does, and a label that lands dead-flat under
  /// the thumb reads as a repaint instead of a response. The bounce is a
  /// quarter of the package's default, so it settles rather than wobbles.
  ///
  /// `interrupt: false` is the important field. A primary button is spam-prone,
  /// and interrupting snaps the in-flight roll to its target before starting the
  /// next one — which on a double tap paints the intermediate label for one
  /// frame. Queueing the latest target instead is what the package recommends
  /// for exactly this case.
  static const command = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 20),
    exitOffset: Duration(milliseconds: 30),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0.15,
    interrupt: false,
  );

  /// The busy loop under [ReelTextController.runWhile].
  ///
  /// Deliberately calmer and shorter than [command]: this one repeats on a timer
  /// for as long as a network call takes, and the same bounce that reads as
  /// tactile on a single press reads as a twitch on a repeating beat.
  ///
  /// The beat is not set here: `reel_text` derives it from this preset when no
  /// `step` is given — the roll ([AppAnimation.durationSm], 200 ms, with no
  /// bounce to stretch it) plus the 24 ms exit offset plus a fixed 160 ms rest,
  /// so one tick every 384 ms, about 2.6 a second. Changing the duration or the
  /// exit offset moves it.
  ///
  /// **This preset is the one place `respectDisableAnimations` does not cover
  /// us.** That flag suppresses the *roll*; it does not stop the controller's
  /// frame timer, so under Reduce Motion an ellipsis loop still hard-swaps
  /// `Testing` → `Testing.` → `Testing..` on that 384 ms beat. Text changing on
  /// a timer with no animation is not motion, but it is still something moving
  /// for a user who asked for less — so callers check
  /// [MediaQuery.disableAnimationsOf] and show a settled label instead. That
  /// check lives in [ReelCommandButton]; do not re-implement it per screen.
  static const waiting = ReelTextOptions(
    direction: ReelTextDirection.down,
    duration: AppAnimation.durationSm,
    stagger: Duration(milliseconds: 16),
    exitOffset: Duration(milliseconds: 24),
    curve: AppAnimation.emphasizedCurve,
    bounce: 0,
  );
}
