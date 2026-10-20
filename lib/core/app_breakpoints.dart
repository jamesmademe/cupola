import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// The window sizes the app is designed at, and the one test that decides which
/// shell paints them.
///
/// Three sizes, drawn rather than derived: 1440x900 (full), 720x450 (compact)
/// and 390x844 (mobile). Everything between them is interpolation, which is why
/// there are only two numbers here and not a scale.
///
/// The important distinction is that [isDesktopShell] asks about the
/// **platform** first and the width only second. A 720pt desktop window still
/// gets the window chrome, the rail and the deck; it just gets their compact
/// variants, while a 900pt iPad must never grow a window strip it has no
/// window for. Only below the compact artboard does a desktop window give the
/// shell up, and then for the phone's layout, drawn for exactly that measure.
/// Width alone cannot tell those two apart, and the shell that tried ended up
/// putting a caption bar on an iPad. The phone used to be the second half of
/// that argument, at roughly 850pt on its side; it is portrait-only now (The
/// Portrait Rule, DESIGN.md) and never reaches those widths at all, which
/// removes an example and none of the reasoning.
abstract final class AppBreakpoints {
  /// Width at or above which a *touch* shell moves its navigation from the
  /// bottom bar to a side rail.
  ///
  /// 840 rather than 600, and the reason has changed shape. It was 840 because
  /// at 600 a phone on its side (roughly 850pt on a modern iPhone) also got
  /// the rail, replacing a thumb-reachable bottom bar on a device held in one
  /// hand. The phone is portrait-only now (The Portrait Rule, DESIGN.md) and
  /// tops out near 440pt, so it can no longer cross either number and the
  /// original argument is moot.
  ///
  /// The number stays, on the other half of its justification: 840 is
  /// Material's expanded-window breakpoint, which is where a touch surface
  /// stops being one-handed: a tablet, an unfolded foldable. Tablets are a
  /// supported layout now: the rail here, and from [touchSplit] a title
  /// opened beside the page it came from.
  static const double touchRail = DesignTokens.breakpointTouchRail;

  /// Width at or above which a *touch* build opens a title beside the page it
  /// was opened from (`MediaSplit`): that page in [splitList] on the left, the
  /// title's page on the right.
  ///
  /// 1024 because below it the title would get less than a phone's column:
  /// the rail's 104 and the list's 440 leave 480 at 1024. An iPad on its side
  /// and a 13-inch one upright clear it; an 11-inch one upright (834) keeps
  /// the full page, as a phone does.
  static const double touchSplit = DesignTokens.breakpointTouchSplit;

  /// The column a page keeps beside an open title: the widest phone, so the
  /// page reads exactly as it does on one.
  static const double splitList = DesignTokens.breakpointSplitList;

  /// Width below which the desktop shell uses its compact variants.
  ///
  /// The two drawn desktop sizes are 1440 and 720; this sits between them,
  /// nearer the top, because the things that collapse: the sidebar's names,
  /// the TrueNAS section list, a second results column; all stop
  /// fitting well before the window is halved. Below it the shell keeps every
  /// part it had and shows fewer items in each, never smaller ones.
  static const double desktopCompact = DesignTokens.breakpointDesktopCompact;

  /// Aspect ratio at or above which a frame stops stacking and starts putting
  /// two things side by side.
  ///
  /// Decision 46, in one number: **the compact frame is not a narrow one.** The
  /// gate is the window's *shape*, not its width. 720x450 is 1.6:1 and gets the
  /// two-column arrangement exactly as 1440x900 does: the drawn compact frame
  /// puts the certificate beside the form at 308pt columns, while the phone, at
  /// 390x844, is the only portrait frame in the flow and the only one that
  /// stacks and scrolls.
  ///
  /// 1.2 rather than a bare `width > height`: the three drawn frames measure
  /// 1.6, 1.6 and 0.46, so anything between them separates the two arrangements,
  /// and a window dragged to nearly square has no room for a second column
  /// whatever its orientation says.
  ///
  /// It sits here rather than in the onboarding feature, where it was born,
  /// with a comment saying it belonged here, because it is a size class like
  /// [touchRail] and [desktopCompact], not a fact about onboarding: any screen
  /// whose two-column arrangement is governed by shape rather than measure asks
  /// this same question. It is *not* a width, which is the whole point:
  /// [desktopCompact] answers "how much room", this answers "what shape", and
  /// the onboarding walk asking the first one is why four drawn compact frames
  /// were code the app could never reach.
  static const double landscapeAspect = DesignTokens.breakpointLandscapeAspect;

  /// Whether [context]'s frame is landscape enough for a side-by-side
  /// arrangement.
  ///
  /// A zero (or absent) height answers false rather than dividing by it: the
  /// first frame of a test harness and a window mid-restore both hand out a
  /// degenerate size, and "stack it" is the safe answer to a frame whose shape
  /// is not known yet.
  static bool isLandscapeFrame(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.height <= 0) return false;
    return size.width / size.height >= landscapeAspect;
  }

  /// Widest the main content well is allowed to grow.
  ///
  /// A dashboard stretched across a 27-inch display is not more information, it
  /// is the same information with the reading line broken. The well centres in
  /// whatever is left after the rail and the inspector.
  static const double contentWell = DesignTokens.breakpointContentWell;

  /// Widest a page of one column grows (an artist's, an author's): its rows
  /// are read top to bottom, and stretched to a desktop window they would be
  /// a line too long to follow.
  static const double readingWell = DesignTokens.breakpointReadingWell;

  /// How far a page read as one column insets its content on each side so
  /// that it stops at [well] and centres: nothing on a phone, or in a pane
  /// no wider than the well.
  ///
  /// Touch and window alike, unlike [DesktopContentWell]: a tablet's page
  /// stretched across 1100pt is as long a line as a window's, and the page
  /// that keeps the column beside an open title is narrower than the well
  /// and is left alone. The list itself stays as wide as its pane, so it
  /// scrolls from anywhere across it.
  static double wellInset(double width, {double well = readingWell}) =>
      width > well ? (width - well) / 2 : 0;

  /// Width below which a desktop window paints the touch shell.
  ///
  /// 720 is the compact artboard, the narrowest frame the window shell is drawn
  /// at: below it the deck has already given up its glyph bands and the
  /// inspector is already closed, so there is nothing left to collapse. Rather
  /// than stopping the window there, a narrower one gets the layout drawn for
  /// that measure (the phone's, bottom bar and all) under a bare drag strip
  /// that keeps the OS window buttons. The window stays frameless either way.
  static const double desktopMobile = DesignTokens.breakpointDesktopMobile;

  /// From this width a sheet is a dialog (`AppBottomSheet`): a form or a
  /// picker centred at 520, a long list in a tall one. The width a desktop
  /// window keeps its own shell from, on a tablet as on a desktop.
  static const double sheetDialog = desktopMobile;

  /// The short side a window needs as well: a phone on its side is 900 wide
  /// and 430 tall, and a dialog there would be a strip. The largest phones
  /// stop short of it; a tablet, a folded-out phone and a desktop window pass.
  static const double sheetDialogShortest = 500;

  /// Whether a sheet shown in [context] is drawn as a dialog: see
  /// [sheetDialog]. The width alone, never the platform.
  static bool sheetsAreDialogs(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= sheetDialog &&
        size.shortestSide >= sheetDialogShortest;
  }

  /// Narrowest a desktop window may be dragged: a small phone's width. Height
  /// stays the compact artboard's, so the 720x450 frame remains reachable.
  static const Size desktopMinimumWindow = Size(
    DesignTokens.breakpointDesktopMinWidth,
    DesignTokens.breakpointDesktopMinHeight,
  );

  /// Whether this build runs in a window it manages itself.
  ///
  /// Answers on the platform, so it is a constant per build: it decides who
  /// owns the window: frameless strip, caption buttons, drag regions; never
  /// which layout paints inside it. For that ask [isDesktopShell].
  ///
  /// [defaultTargetPlatform] rather than `Platform.isMacOS`, and the difference
  /// matters: widget tests run on a developer's Mac, so `dart:io` would answer
  /// "desktop" for every test in the suite and quietly re-point the whole
  /// mobile shell at the window layout. `defaultTargetPlatform` is Android
  /// under `flutter_test` unless a test says otherwise, so each shell is tested
  /// by asking for it.
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Whether [context]'s window draws the desktop shell: chrome, rail, deck.
  ///
  /// The platform first, then the width. A 900pt iPad never qualifies; it has
  /// no window to put a caption bar on, while a desktop window dragged under
  /// [desktopMobile] stops qualifying and gets the phone layout. A resize may
  /// cross it all day: the branch navigators are keyed globally, so their
  /// stacks survive the swap between shells.
  static bool isDesktopShell(BuildContext context) =>
      isDesktopPlatform && MediaQuery.sizeOf(context).width >= desktopMobile;

  /// Whether this desktop window is narrow enough for the compact variants.
  ///
  /// False on every touch build and on a desktop window painting the touch
  /// shell, so a caller can ask it without first asking [isDesktopShell].
  static bool isCompactDesktop(BuildContext context) {
    if (!isDesktopShell(context)) return false;
    return MediaQuery.sizeOf(context).width < desktopCompact;
  }
}
