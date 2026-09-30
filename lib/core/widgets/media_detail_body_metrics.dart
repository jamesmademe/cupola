import 'dart:math' as math;

import 'package:cupola/core/app_spacing.dart';

/// Measure of the media detail body's content column.
///
/// The hero is deliberately excluded: a backdrop is art and stays full-bleed.
/// Everything below it reads as one column, and on a resizable macOS window that
/// column has to stop growing — an overview paragraph running 1400pt wide is not
/// a wide layout, it is an unreadable one.
class MediaDetailMetrics {
  MediaDetailMetrics._();

  /// Widest the body column is allowed to get.
  ///
  /// 720 keeps a three-across 130pt poster rail (3 x 130 + 2 x 12 + 2 x 16 =
  /// 438) and the fact grid's 320pt two-column threshold comfortably inside,
  /// while stopping a full-window overview from running the whole width of a
  /// maximised macOS window.
  static const double bodyMaxWidth = 720;

  /// Measure for running prose, nested inside [bodyMaxWidth].
  ///
  /// `bodyLarge` (Onest 15 on 22) lands near 75 characters at
  /// `640 - 2 x 16`, the top of the comfortable reading range. Wider than that
  /// and the eye loses the line it came from on the return sweep.
  static const double proseMaxWidth = 640;

  /// Width of the desktop side track.
  ///
  /// 380, which is what every `Detail*.dc.html` board draws — all nine are
  /// `grid-template-columns: minmax(0, 1fr) 380px`. It was 300, as a bare local
  /// inside the two-track emitter, and 300 is below the measure the side track's
  /// content is drawn at: a Details grid whose value column has to hold
  /// `Ultra-HD Bluray + WEB 2160p` and a Collection tile rail both wrap at 300
  /// and neither does at 380.
  static const double sideTrackWidth = 380;

  /// Horizontal inset for a slot that runs the whole track.
  ///
  /// The screen gutter and nothing else. [gutterOf] centres a reading column by
  /// splitting the surplus, which is right for prose and wrong for a table: a
  /// season table capped at [bodyMaxWidth] inside a 1000pt window is a table
  /// with a 140pt margin on each side, not a readable measure. A table and a
  /// grid are read down their columns, not across their lines, so the return
  /// sweep argument that justifies [bodyMaxWidth] does not apply to them.
  static const double trackGutter = AppSpacing.lg;

  /// Horizontal inset for every body slot at [availableWidth].
  ///
  /// Below [bodyMaxWidth] this is exactly `AppSpacing.lg`, the app's screen
  /// padding; above it the surplus is split evenly so the column centres. One
  /// number for every slot is what removes the mid-page jog a section that
  /// inset itself at `AppSpacing.xl` used to produce.
  static double gutterOf(double availableWidth) =>
      AppSpacing.lg + math.max(0.0, (availableWidth - bodyMaxWidth) / 2);
}
