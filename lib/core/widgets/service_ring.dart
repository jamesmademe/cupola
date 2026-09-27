import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The ring gives up size as the reading size grows, so the copy beside it never
/// loses room — the Column Floor Rule applied to a diagram instead of a grid.
double serviceRingDiameter(
  BuildContext context, {
  required double preferred,
  double horizontalPadding = AppSpacing.xl * 2,
}) {
  final available =
      MediaQuery.sizeOf(context).width - horizontalPadding - AppSpacing.xl;
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final shrunk = preferred / scale.clamp(1.0, 1.6);
  return shrunk.clamp(96.0, available.clamp(96.0, preferred));
}

/// What one service's node on the ring is currently saying.
enum ServiceRingState {
  /// Not chosen. A dim dot, the smallest thing on the ring.
  unlit,

  /// Chosen but not yet reached — its accent, held back.
  picked,

  /// Answering. Full accent, a glow, and a spoke drawn in to the mark.
  connected,

  /// Configured and not answering. Drains to `onSurfaceVariant` with a hairline
  /// collar, because on this ring hue carries identity and never health — an
  /// unreachable service reads as unlit, not as differently coloured.
  silent,
}

/// The stack as a dial: every service is a dot on one circle around the product
/// mark, and a connected service draws a spoke to the centre.
///
/// This is the second sanctioned exception to the Room Light Rule, on the same
/// terms as `/services`: the surface is inherently about every service at
/// once, so accents are *confined* — a service's colour appears on its own node
/// and nowhere else. Nothing on the ring borrows a status tone.
///
/// **The ring animates itself.** Every visual a node can carry — radius, colour,
/// glow, collar, the length of its spoke — interpolates from whatever it was
/// showing to whatever it should show, so a service lighting up or draining is a
/// move rather than a cut. The caller changes [states] and nothing else. That is
/// also what lets one instance live *above* a pager and survive navigation
/// between the services being configured: the instrument is the fixed frame, the
/// forms are what page.
class ServiceRing extends StatefulWidget {
  const ServiceRing({
    super.key,
    required this.states,
    required this.diameter,
    this.entrance = 1,
    this.progress = 0,
    this.activeService,
    this.spin = false,
    this.markFraction = defaultMarkFraction,
  });

  /// The mark's share of the ring when the ring is the subject of the screen.
  ///
  /// Named so a caller that wants a different proportion can say what it is
  /// departing *from* — see [markFraction].
  static const double defaultMarkFraction = 0.42;

  /// Per-service node state. A service absent from the map is
  /// [ServiceRingState.unlit].
  final Map<ServiceKey, ServiceRingState> states;

  /// Already-interpolated by the caller when it changes between screens, so the
  /// ring and the space it sits in resize on one clock rather than two.
  final double diameter;

  /// 0 → nodes still gathered at the mark, 1 → seated on the ring. The one
  /// caller-driven value: it is the flow's opening moment, not a state change.
  final double entrance;

  /// Fraction of the walk completed, drawn as an arc from noon clockwise.
  final double progress;

  /// Wears a collar and a glow while it is the service being configured.
  ///
  /// It is *marked*, not positioned. Parking the active node at noon was tried
  /// and it fights the sweep — the dial turns, so the node parked at the top
  /// drifts off it within a second, and the two rotations read as a bug rather
  /// than as either intention. The collar and the halo carry the job instead.
  final ServiceKey? activeService;

  /// A slow continuous sweep.
  ///
  /// Ambient motion is otherwise against the house rule, and this is the one
  /// carve-out: the ring is an instrument dial, one revolution takes 96 seconds
  /// — slower than anything else the app moves — it exists only where the ring
  /// is the subject of the screen, and Reduce Motion stops it dead.
  final bool spin;

  /// The mark's width as a fraction of the ring's diameter.
  final double markFraction;

  /// Services in ring order: registry order, grouped into domain arcs.
  static List<ServiceKey> get order => [
    for (final domain in ServiceDomain.values) ...domain.services,
  ];

  @override
  State<ServiceRing> createState() => _ServiceRingState();
}

class _ServiceRingState extends State<ServiceRing>
    with TickerProviderStateMixin {
  /// One revolution. Long enough to read as a live instrument rather than a
  /// spinner: at this rate a node crosses its own width in about two seconds.
  static const _spinPeriod = Duration(seconds: 96);

  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: AppAnimation.durationLg,
  );

  late final AnimationController _spinner = AnimationController(
    vsync: this,
    duration: _spinPeriod,
  );

  /// The frame the ring was showing when the current transition began, so an
  /// interrupted change continues from what is on screen instead of snapping
  /// back to the previous target.
  _RingFrame? _from;

  /// The frame last painted. Written during build deliberately: it is a record
  /// of output, never a trigger for one.
  _RingFrame? _painted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpinner();
  }

  @override
  void didUpdateWidget(ServiceRing old) {
    super.didUpdateWidget(old);
    if (old.spin != widget.spin) _syncSpinner();
    final changed =
        !_sameStates(old.states, widget.states) ||
        old.activeService != widget.activeService ||
        old.progress != widget.progress;
    if (!changed) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Removing the animator, not shortening it.
      _from = null;
      _transition.value = 1;
      return;
    }
    _from = _painted;
    _transition.forward(from: 0);
  }

  void _syncSpinner() {
    final wanted = widget.spin && !MediaQuery.disableAnimationsOf(context);
    if (wanted && !_spinner.isAnimating) {
      _spinner.repeat();
    } else if (!wanted && _spinner.isAnimating) {
      _spinner.stop();
    }
  }

  static bool _sameStates(
    Map<ServiceKey, ServiceRingState> a,
    Map<ServiceKey, ServiceRingState> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _transition.dispose();
    _spinner.dispose();
    super.dispose();
  }

  String _spoken() {
    final picked = widget.states.values
        .where((s) => s != ServiceRingState.unlit)
        .length;
    final connected = widget.states.values
        .where((s) => s == ServiceRingState.connected)
        .length;
    final silent = widget.states.values
        .where((s) => s == ServiceRingState.silent)
        .length;
    if (picked == 0) {
      return '${ServiceKey.values.length} services, none set up yet';
    }
    final parts = <String>['$picked of ${ServiceKey.values.length} chosen'];
    if (connected > 0) parts.add('$connected answering');
    if (silent > 0) parts.add('$silent not answering');
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _RingFrame.resolve(
      states: widget.states,
      activeService: widget.activeService,
      progress: widget.progress,
      scheme: theme.colorScheme,
      isDark: theme.brightness == Brightness.dark,
    );

    return Semantics(
      label: _spoken(),
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.diameter,
          height: widget.diameter,
          child: AnimatedBuilder(
            animation: Listenable.merge([_transition, _spinner]),
            builder: (context, _) {
              final t = AppAnimation.emphasizedCurve.transform(
                _transition.value,
              );
              final frame = _from == null
                  ? target
                  : _RingFrame.lerp(_from!, target, t);
              _painted = frame;
              return CustomPaint(
                painter: _ServiceRingPainter(
                  frame: frame,
                  entrance: widget.entrance,
                  sweep: _spinner.value * math.pi * 2,
                ),
                child: Center(
                  child: Opacity(
                    opacity: widget.entrance,
                    child: SizedBox(
                      width: widget.diameter * widget.markFraction,
                      height: widget.diameter * widget.markFraction,
                      child: const _Mark(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Everything the painter needs, resolved and interpolable.
///
/// Resolving to numbers and colours up front is what makes the animation
/// possible at all: an enum cannot be lerped, and interpolating the *drawing*
/// rather than the state is what turns a node lighting up into a move.
@immutable
class _RingFrame {
  const _RingFrame({
    required this.nodes,
    required this.progress,
    required this.track,
  });

  final List<_NodeVisual> nodes;
  final double progress;
  final Color track;

  static _RingFrame resolve({
    required Map<ServiceKey, ServiceRingState> states,
    required ServiceKey? activeService,
    required double progress,
    required ColorScheme scheme,
    required bool isDark,
  }) {
    // The diagram's ink, and the reason it is not taken from the surface ladder:
    // a graphic drawn out of `outlineVariant` and `surfaceContainerHigh`
    // measures 1.16:1 and 1.03:1 on `surface-light`, because the light ladder's
    // steps are deliberately close together. `onSurfaceVariant` at a
    // per-brightness alpha gives both themes the same perceptual weight instead
    // — the hairline lands near 1.8:1 in each, and an unlit dot clears the 3:1
    // non-text floor in each (3.9:1 dark, 4.6:1 light) where one shared 55%
    // measured 1.9:1 on white.
    final unlit = scheme.onSurfaceVariant.withValues(
      alpha: isDark ? 0.55 : 0.80,
    );
    // A soft accent halo washes out faster on a light ground.
    final glowAlpha = isDark ? 0.34 : 0.42;
    final spokeAlpha = isDark ? 0.55 : 0.70;

    return _RingFrame(
      track: scheme.onSurfaceVariant.withValues(alpha: 0.30),
      progress: progress,
      nodes: [
        for (final key in ServiceRing.order)
          switch (states[key] ?? ServiceRingState.unlit) {
            ServiceRingState.unlit => _NodeVisual(
              accent: key.accent,
              radius: 4,
              color: unlit,
              glow: 0,
              spoke: 0,
              collar: 0,
              collarColor: key.accent,
              spokeAlpha: spokeAlpha,
            ),
            ServiceRingState.picked => _NodeVisual(
              accent: key.accent,
              radius: 5,
              color: key.accent.withValues(alpha: 0.78),
              glow: activeService == key ? glowAlpha : 0,
              spoke: 0,
              collar: activeService == key ? 1 : 0,
              collarColor: key.accent.withValues(alpha: 0.6),
              spokeAlpha: spokeAlpha,
            ),
            ServiceRingState.connected => _NodeVisual(
              accent: key.accent,
              radius: 6,
              color: key.accent,
              glow: glowAlpha,
              spoke: 1,
              collar: activeService == key ? 1 : 0,
              collarColor: key.accent.withValues(alpha: 0.6),
              spokeAlpha: spokeAlpha,
            ),
            ServiceRingState.silent => _NodeVisual(
              accent: key.accent,
              radius: 5,
              color: scheme.onSurfaceVariant,
              glow: activeService == key ? glowAlpha : 0,
              spoke: 0,
              collar: 1,
              collarColor: activeService == key
                  ? key.accent.withValues(alpha: 0.6)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.35),
              spokeAlpha: spokeAlpha,
            ),
          },
      ],
    );
  }

  static _RingFrame lerp(_RingFrame a, _RingFrame b, double t) => _RingFrame(
    track: Color.lerp(a.track, b.track, t)!,
    progress: a.progress + (b.progress - a.progress) * t,
    nodes: [
      for (var i = 0; i < b.nodes.length; i++)
        _NodeVisual.lerp(
          i < a.nodes.length ? a.nodes[i] : b.nodes[i],
          b.nodes[i],
          t,
        ),
    ],
  );
}

@immutable
class _NodeVisual {
  const _NodeVisual({
    required this.accent,
    required this.radius,
    required this.color,
    required this.glow,
    required this.spoke,
    required this.collar,
    required this.collarColor,
    required this.spokeAlpha,
  });

  final Color accent;
  final double radius;
  final Color color;

  /// Peak alpha of the halo behind the dot; 0 for no halo.
  final double glow;

  /// How far the spoke has grown from the mark out to the node, 0–1.
  final double spoke;

  /// Opacity of the hairline ring around the dot.
  final double collar;
  final Color collarColor;
  final double spokeAlpha;

  static _NodeVisual lerp(_NodeVisual a, _NodeVisual b, double t) =>
      _NodeVisual(
        accent: Color.lerp(a.accent, b.accent, t)!,
        radius: a.radius + (b.radius - a.radius) * t,
        color: Color.lerp(a.color, b.color, t)!,
        glow: a.glow + (b.glow - a.glow) * t,
        spoke: a.spoke + (b.spoke - a.spoke) * t,
        collar: a.collar + (b.collar - a.collar) * t,
        collarColor: Color.lerp(a.collarColor, b.collarColor, t)!,
        spokeAlpha: a.spokeAlpha + (b.spokeAlpha - a.spokeAlpha) * t,
      );
}

/// The product mark — the Cupola from above: six lit window panes around the
/// central circular window. The ring's own nodes orbit it, so the mark supplies
/// the structure and never a second ring.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/cupola_mark.png',
    fit: BoxFit.contain,
    // Decorative here: [ServiceRing] already publishes the ring's meaning.
    excludeFromSemantics: true,
  );
}

/// Where each node sits, and how the circle divides into domain arcs.
///
/// Computed once: the geometry only depends on the registry, so the ring's
/// layout is a property of the stack rather than of a screen.
abstract final class _RingGeometry {
  /// Blank slots inserted between two domains, in node-widths. Wide enough to
  /// read as a gap, narrow enough that fifteen nodes still fill the circle.
  static const gap = 1.7;

  static final List<double> angles = _computeAngles();
  static final List<double> domainStarts = _computeDomainStarts();

  static double get _unit =>
      (math.pi * 2) /
      (ServiceKey.values.length + gap * ServiceDomain.values.length);

  static List<double> _computeAngles() {
    final out = <double>[];
    var slot = gap / 2;
    for (final domain in ServiceDomain.values) {
      for (var i = 0; i < domain.services.length; i++) {
        out.add(-math.pi / 2 + _unit * (slot + 0.5));
        slot += 1;
      }
      slot += gap;
    }
    return out;
  }

  static List<double> _computeDomainStarts() {
    final out = <double>[];
    var slot = 0.0;
    for (final domain in ServiceDomain.values) {
      out.add(-math.pi / 2 + _unit * slot);
      slot += domain.services.length + gap;
    }
    return out;
  }
}

class _ServiceRingPainter extends CustomPainter {
  _ServiceRingPainter({
    required this.frame,
    required this.entrance,
    required this.sweep,
  });

  final _RingFrame frame;
  final double entrance;

  /// The ambient rotation, kept separate from the frame so the sweep continues
  /// through a state transition instead of being interpolated by it.
  final double sweep;

  /// Room for the largest node plus its collar, so nothing clips at the rim.
  static const _nodeHalo = 14.0;

  double get _rotation => sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _nodeHalo;

    _paintTrack(canvas, centre, radius);
    _paintProgress(canvas, centre, radius);
    // Spokes first so the dots sit on top of them.
    _paintSpokes(canvas, centre, radius);
    _paintNodes(canvas, centre, radius);
  }

  void _paintTrack(Canvas canvas, Offset centre, double radius) {
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = frame.track,
    );
    // One tick where each domain arc begins — what makes the circle read as a
    // four-sector dial rather than a wreath.
    for (final angle in _RingGeometry.domainStarts) {
      final a = angle + _rotation;
      final direction = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        centre + direction * (radius - 5),
        centre + direction * (radius + 5),
        Paint()
          ..strokeWidth = 1
          ..color = frame.track,
      );
    }
  }

  void _paintProgress(Canvas canvas, Offset centre, double radius) {
    if (frame.progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2 + _rotation,
      math.pi * 2 * frame.progress.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        // Barely heavier than the 1px track, and translucent: this is the part
        // of the dial that is *lit*, not a second object laid over it. At full
        // weight and opacity a half-swept arc outshouted the fifteen nodes it
        // exists to serve.
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary.withValues(alpha: 0.5),
    );
  }

  void _paintSpokes(Canvas canvas, Offset centre, double radius) {
    for (var i = 0; i < frame.nodes.length; i++) {
      final node = frame.nodes[i];
      if (node.spoke <= 0.001) continue;
      final a = _RingGeometry.angles[i] + _rotation;
      final direction = Offset(math.cos(a), math.sin(a));
      final start = centre + direction * (radius * 0.34);
      // Grows outward from the mark to the node, so a service connecting reads
      // as a line being drawn *in* rather than a line appearing.
      final full = radius * entrance - 9;
      final end =
          centre +
          direction * (radius * 0.34 + (full - radius * 0.34) * node.spoke);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [
              node.accent.withValues(alpha: 0.05 * node.spoke),
              node.accent.withValues(alpha: node.spokeAlpha * node.spoke),
            ],
          ).createShader(Rect.fromPoints(start, end)),
      );
    }
  }

  void _paintNodes(Canvas canvas, Offset centre, double radius) {
    for (var i = 0; i < frame.nodes.length; i++) {
      final node = frame.nodes[i];
      final a = _RingGeometry.angles[i] + _rotation;
      final point =
          centre + Offset(math.cos(a), math.sin(a)) * (radius * entrance);

      if (node.glow > 0.001) {
        final haloRadius = node.radius * 3.4;
        canvas.drawCircle(
          point,
          haloRadius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                node.accent.withValues(alpha: node.glow),
                node.accent.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: point, radius: haloRadius)),
        );
      }

      canvas.drawCircle(point, node.radius, Paint()..color = node.color);

      if (node.collar > 0.001) {
        canvas.drawCircle(
          point,
          node.radius + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = node.collarColor.withValues(
              alpha: node.collarColor.a * node.collar,
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ServiceRingPainter old) =>
      old.entrance != entrance || old.sweep != sweep || old.frame != frame;
}

/// The punchline, and the reason it is here rather than inlined in onboarding:
/// the claim is meant to be *shared* — the same two lines in the same two inks
/// carry the dashboard's empty state, so the door prints a claim rather than
/// owning one.
///
/// It used to assert that the empty state already did; it does not. That screen
/// still prints a headline of its own, and swapping it belongs to the dashboard
/// rather than here — a doc that describes an intention as a fact is worse than
/// no doc, because it is the one place a reader would check before changing
/// either side.
///
/// Two accents, and they are the mark's own two — the ribbon "S" runs cyan to
/// blue, so the sentence takes the blue end for the product's own name and the
/// cyan end for the user's own lab. The cyan is a `nav-*` section accent rather
/// than a service's, because colouring "your lab" with one service's identity
/// would privilege it over the other fourteen.
class OnePunchline extends StatelessWidget {
  const OnePunchline({super.key, this.style});

  /// Defaults to `displayMedium` — the ramp's own step between a heading and a
  /// hero line. Pass a smaller role where the claim is a caption, not the door.
  ///
  /// The weight comes from the role and is not forced here: 800 belongs to
  /// Display, so the door reads at 800 and a caption keeps its own weight.
  final TextStyle? style;

  static const _appInk = AppColors.primary;
  static const _stackInk = AppColors.navActivity;
  static const _spoken = 'A Cupola over your lab.';
  static const _markedLine = 'your lab.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 1.10 is the display leading floor; two lines of heavy type tighter than
    // that start to touch.
    final base = (style ?? theme.textTheme.displayMedium!).copyWith(
      color: scheme.onSurface,
      height: 1.10,
    );

    // Both inks resolve against the composite they sit on. The cyan proves why
    // that is not optional: raw #06B6D4 measures 8.1:1 on `surface-dark` but
    // 2.20:1 on `surface-light`, below even the 3:1 large-text floor.
    final appInk = ServiceTheme.onTint(
      _appInk,
      surface: scheme.surface,
      tintAlpha: 0,
    );
    final stackInk = ServiceTheme.onTint(
      _stackInk,
      surface: scheme.surface,
      tintAlpha: 0,
    );

    return Semantics(
      label: _spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'A '),
                TextSpan(
                  text: 'Cupola',
                  style: TextStyle(color: appInk),
                ),
                const TextSpan(text: ' over'),
              ],
            ),
            style: base,
          ),
          Text(_markedLine, style: base.copyWith(color: stackInk)),
        ],
      ),
    );
  }
}
