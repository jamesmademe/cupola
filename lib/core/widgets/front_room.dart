import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/theme.dart';

/// The light of the room in front, for the chrome that floats over every room:
/// the enamel of the bar and the rail carries a sheen of it, and their pill a
/// tint (brand book, *The title light*).
///
/// A room says its light here while it is in front: its branch is the one the
/// shell shows ([BranchActivityScope]) and its page is its navigator's current
/// one. Of the rooms in front the deepest wins, since a room inside another (a
/// service's tab inside the service's room) is the one painted; of two as deep
/// (a title beside its list on a tablet), the one that came in front last.
/// With no room in front (a sheet over the page) the light is kept. Null is
/// the lamp: a room no title lights casts no sheen.
class FrontRoomLight extends ChangeNotifier {
  final Map<Object, ({int depth, int order, Color? light})> _rooms = {};
  var _order = 0;
  Color? _light;
  var _disposed = false;

  /// The light of the room in front, or null for the lamp.
  Color? get light => _light;

  void _report(Object room, int depth, Color? light) {
    final order = _rooms[room]?.order ?? _order++;
    _rooms[room] = (depth: depth, order: order, light: light);
    _settle();
  }

  void _leave(Object room) {
    if (_rooms.remove(room) != null) _settle();
  }

  void _settle() {
    // A room's leave is posted after the frame, and the shell may have
    // disposed the board in between. Notifying a disposed notifier is a debug
    // assertion and, in release, a write into a dead listener list.
    if (_disposed || _rooms.isEmpty) return;
    final front = _rooms.values.reduce(
      (a, b) => b.depth > a.depth || (b.depth == a.depth && b.order > a.order)
          ? b
          : a,
    );
    if (front.light == _light) return;
    _light = front.light;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Where the rooms below find the [FrontRoomLight] they report to: the shell,
/// over its branches and its bar.
class FrontRoomScope extends InheritedWidget {
  const FrontRoomScope({super.key, required this.light, required super.child});

  final FrontRoomLight light;

  /// The board above [context], read without depending on it: a room reports
  /// to it, and only the chrome listens.
  static FrontRoomLight? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FrontRoomScope>()?.light;

  @override
  bool updateShouldNotify(FrontRoomScope oldWidget) => light != oldWidget.light;
}

/// Says [light] to the [FrontRoomScope] above while the room it stands in is
/// in front ([FrontRoomLight]). The room itself (`AmbientBackground`) wraps
/// its page in one.
class FrontRoomReporter extends StatefulWidget {
  const FrontRoomReporter({
    super.key,
    required this.light,
    required this.child,
  });

  /// The room's light, or null for the lamp.
  final Color? light;
  final Widget child;

  @override
  State<FrontRoomReporter> createState() => _FrontRoomReporterState();
}

class _FrontRoomReporterState extends State<FrontRoomReporter> {
  /// What this room is to the board: outlives the state, so a room that has
  /// gone can still be taken off after the frame it went in.
  final Object _token = Object();
  FrontRoomLight? _board;
  var _depth = 0;
  var _front = false;
  var _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _board = FrontRoomScope.maybeOf(context);
    var depth = 0;
    for (
      var above = context.findAncestorStateOfType<_FrontRoomReporterState>();
      above != null;
      above = above.context.findAncestorStateOfType<_FrontRoomReporterState>()
    ) {
      depth++;
    }
    _depth = depth;
    // Both read with a dependency, so a branch put away or a page pushed over
    // this one comes back here.
    _front =
        BranchActivityScope.isActiveOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _schedule();
  }

  @override
  void didUpdateWidget(FrontRoomReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.light != widget.light) _schedule();
  }

  /// Reports once the frame is built: the chrome listening is built in the
  /// same frame, and may not be marked to build again while it is.
  void _schedule() {
    if (_board == null || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final board = _board;
      if (!mounted || board == null) return;
      if (_front) {
        board._report(_token, _depth, widget.light);
      } else {
        board._leave(_token);
      }
    });
  }

  @override
  void dispose() {
    final board = _board;
    final token = _token;
    // After the frame: a room goes while the tree is locked.
    if (board != null) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => board._leave(token),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The colours the floating chrome takes from the room in front: the sheen at
/// the top of its enamel and the fill of its pill, drifting to a new room's
/// over [AppAnimation.light] as the room's own light does, and simply there
/// under Reduce Motion.
class RoomSheen extends StatelessWidget {
  const RoomSheen({super.key, required this.builder});

  final Widget Function(BuildContext context, Color sheen, Color pill) builder;

  /// How much of the room's light the enamel's top carries.
  static const double sheenStrength = 0.14;

  /// How strongly the pill is tinted: the light in the dark room, the title's
  /// day primary on paper.
  static const double pillTint = 0.18;

  /// The sheen and the pill for [light] (null for the lamp: plain enamel and
  /// the room's strong fill).
  static ({Color sheen, Color pill}) colorsOf(
    BuildContext context,
    Color? light,
  ) {
    final room = CupolaRoom.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (light == null) return (sheen: room.enamel, pill: room.fillStrong);
    final hct = Hct.fromInt(light.toARGB32());
    final tint = dark
        ? light
        // The title's tinted primary on paper (`TitleLight.dayPrimary`), read
        // back from its light: the same hue and chroma at tone 40.
        : Color(Hct.from(hct.hue, hct.chroma.clamp(16, 48), 40).toInt());
    return (
      sheen: Color.lerp(room.enamel, light, sheenStrength)!,
      pill: tint.withValues(alpha: pillTint),
    );
  }

  @override
  Widget build(BuildContext context) {
    final board = FrontRoomScope.maybeOf(context);
    if (board == null) {
      final colors = colorsOf(context, null);
      return builder(context, colors.sheen, colors.pill);
    }
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) {
        final colors = colorsOf(context, board.light);
        if (MediaQuery.disableAnimationsOf(context)) {
          return builder(context, colors.sheen, colors.pill);
        }
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: colors.sheen),
          duration: AppAnimation.light,
          curve: AppAnimation.standardCurve,
          builder: (context, sheen, _) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: colors.pill),
            duration: AppAnimation.light,
            curve: AppAnimation.standardCurve,
            builder: (context, pill, _) =>
                builder(context, sheen ?? colors.sheen, pill ?? colors.pill),
          ),
        );
      },
    );
  }
}
