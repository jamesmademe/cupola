/// The Home's carousel: up to three titles, each with its artwork, its line
/// and its two ways forward, moving on by itself and stopping whenever a
/// person is in the middle of something.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/features/media/presentation/media_parts.dart'
    show mediaLeadStyle;

/// One of a slide's two buttons.
@immutable
class FeaturedAction {
  const FeaturedAction(this.label, this.onTap, {this.icon});

  final String label;
  final VoidCallback onTap;

  /// Before the label: the play glyph on `Resume` and `Play`.
  final IconData? icon;
}

/// One slide, as the pager draws it.
@immutable
class FeaturedPage {
  const FeaturedPage({
    required this.title,
    required this.line,
    required this.art,
    required this.label,
    required this.onOpen,
    required this.lead,
    this.second,
    this.light,
  });

  final String title;

  /// The line under the title: `Continue watching · S2 E3 · 5 min left`.
  final String line;

  /// The wide artwork.
  final ImageSource art;

  /// What the artwork says to a screen reader, which opens [onOpen]: the
  /// title and its line, in one sentence.
  final String label;

  /// The artwork's tap: the title's page.
  final VoidCallback onOpen;

  /// The lit button, filled with the slide's light.
  final FeaturedAction lead;

  /// The quiet button beside it.
  final FeaturedAction? second;

  /// The slide's light, once its artwork is read; null for the lamp.
  final TitleLight? light;
}

/// Up to three slides, one in front, moving on every [AppAnimation.dwell].
///
/// **Movement.** The artwork crossfades over [AppAnimation.imageCrossfade]
/// and drifts (Ken Burns, [AppAnimation.kenBurnsFrom] to
/// [AppAnimation.kenBurnsTo] over [AppAnimation.kenBurns], each slide on its
/// own clock, which runs only while it is in front); the copy crossfades
/// over [AppAnimation.textCrossfade], rising [AppAnimation.textCrossfadeRise].
/// The pill of the slide in front fills as its time runs.
///
/// **It stops** while a finger is down and for [AppAnimation.dwellHold]
/// after, while less than half of it is on screen, while the page is not the
/// one in front ([live]) and the app is away (its ticker is muted), and with
/// the pause control. With a screen reader or Reduce Motion it starts
/// paused: the dots become buttons (`Show slide 2 of 3`) and the control
/// reads Play. Reduce Motion also drops the drift and the rise, and every
/// crossfade takes 150 ms.
///
/// **Touch safety.** A button acts on the slide that was in front when the
/// finger came down: a touch in the first half of a change brings the
/// slide that was leaving back, and it is that slide's action that runs.
///
/// One slide: no pager, no control, nothing moves.
class FeaturedPager extends StatefulWidget {
  const FeaturedPager({
    super.key,
    required this.pages,
    this.initialIndex = 0,
    this.onShown,
    this.onArtDrawn,
    this.live = true,
    this.advances = true,
  });

  final List<FeaturedPage> pages;

  /// The slide in front when the pager is built.
  final int initialIndex;

  /// Told the index of the slide that comes to the front.
  final ValueChanged<int>? onShown;

  /// Told the address of each artwork once it is drawn.
  final ValueChanged<String>? onArtDrawn;

  /// Whether the page is the one on screen (`watchPageActivity`).
  final bool live;

  /// Whether the slides move on by themselves; off where a page is settled
  /// frame by frame.
  final bool advances;

  /// The artwork's height for a pager [width] wide: 214 on the phone,
  /// growing with the well as the Media page's backdrop does.
  static double artHeightFor(double width) => (width / 2.6).clamp(214, 420);

  /// The crossfade under Reduce Motion.
  static const quietFade = Duration(milliseconds: 150);

  @override
  State<FeaturedPager> createState() => _FeaturedPagerState();
}

enum _Role { lead, second, open }

class _FeaturedPagerState extends State<FeaturedPager>
    with TickerProviderStateMixin {
  late final AnimationController _dwell = AnimationController(
    vsync: this,
    duration: AppAnimation.dwell,
  )..addStatusListener(_onDwell);

  late int _index = _clamp(widget.initialIndex);

  /// The slide that left the front at the last change, and how far the
  /// copy's crossfade has gone since: on the frame clock, as the eye sees it.
  int? _leaving;
  late final AnimationController _change = AnimationController(
    vsync: this,
    duration: AppAnimation.textCrossfade,
    value: 1,
  );

  /// The pause control: null until it is used, then what it says.
  bool? _pausedByChoice;

  bool _held = false;
  Timer? _release;

  bool _onScreen = true;
  ScrollPosition? _position;

  /// How many seconds each slide's artwork has drifted while in front.
  late List<double> _drift = List.filled(widget.pages.length, 0);

  double _dragged = 0;

  static final _dwellSeconds =
      AppAnimation.dwell.inMilliseconds / Duration.millisecondsPerSecond;

  int _clamp(int index) =>
      widget.pages.isEmpty ? 0 : index.clamp(0, widget.pages.length - 1);

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// A screen reader or Reduce Motion: nothing moves on until asked.
  bool get _quiet =>
      _reduceMotion || MediaQuery.accessibleNavigationOf(context);

  bool get _paused => _pausedByChoice ?? _quiet;

  bool get _several => widget.pages.length > 1;

  bool get _running =>
      widget.advances &&
      widget.live &&
      _several &&
      !_paused &&
      !_held &&
      _onScreen;

  void _sync() {
    if (!mounted) return;
    if (_running) {
      if (!_dwell.isAnimating) _dwell.forward();
    } else if (_dwell.isAnimating) {
      _dwell.stop();
    }
  }

  void _onDwell(AnimationStatus status) {
    if (status == AnimationStatus.completed) _go(_index + 1);
  }

  /// Brings slide [to] to the front, its pill empty.
  void _go(int to) {
    final count = widget.pages.length;
    if (count == 0) return;
    final next = to % count;
    if (next == _index) return;
    _drift[_index] += _dwell.value * _dwellSeconds;
    setState(() {
      _leaving = _index;
      _index = next;
    });
    _change
      ..duration = _copyFade
      ..forward(from: 0);
    _dwell.value = 0;
    widget.onShown?.call(next);
    _sync();
  }

  void _down(PointerDownEvent event) {
    _release?.cancel();
    // In the first half of a change the eye is still on the slide leaving:
    // it comes back, and it is the one the touch acts on.
    final leaving = _leaving;
    if (leaving != null && _change.value < 0.5) {
      _drift[_index] += _dwell.value * _dwellSeconds;
      setState(() {
        _index = leaving;
        _leaving = null;
      });
      _change.value = 1;
      _dwell.value = 0;
      widget.onShown?.call(leaving);
    }
    _held = true;
    _sync();
  }

  void _up(PointerEvent event) {
    _release?.cancel();
    _release = Timer(AppAnimation.dwellHold, () {
      _held = false;
      _sync();
    });
  }

  /// What a button or the artwork does, on the slide in front now: the one
  /// the finger came down on.
  void _act(_Role role) {
    final page = widget.pages[_index];
    switch (role) {
      case _Role.lead:
        page.lead.onTap();
      case _Role.second:
        page.second?.onTap();
      case _Role.open:
        page.onOpen();
    }
  }

  void _togglePause() {
    setState(() => _pausedByChoice = !_paused);
    _sync();
  }

  void _dragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragged;
    _dragged = 0;
    if (distance.abs() < 40 && velocity.abs() < 300) return;
    final forward = distance.abs() >= 40 ? distance < 0 : velocity < 0;
    _go(_index + (forward ? 1 : -1));
  }

  // --- On screen -----------------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_measure);
      _position = position?..addListener(_measure);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    _sync();
  }

  /// Whether at least half of the pager is inside its scroll view.
  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final view = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.height == 0) return;
    var onScreen = true;
    if (view is RenderBox && view.hasSize) {
      final top = box.localToGlobal(Offset.zero, ancestor: view).dy;
      final bottom = top + box.size.height;
      final shown =
          (bottom.clamp(0, view.size.height) - top.clamp(0, view.size.height)) /
          box.size.height;
      onScreen = shown >= 0.5;
    }
    if (onScreen != _onScreen) {
      _onScreen = onScreen;
      _sync();
    }
  }

  @override
  void didUpdateWidget(FeaturedPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages.length != widget.pages.length) {
      _drift = List.filled(widget.pages.length, 0);
      _index = _clamp(_index);
      _leaving = null;
      _dwell.value = 0;
    }
    _sync();
  }

  @override
  void dispose() {
    _release?.cancel();
    _position?.removeListener(_measure);
    _change.dispose();
    _dwell.dispose();
    super.dispose();
  }

  // --- Drawing -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    final quiet = _quiet && _several;
    // At a large reading size the title takes the whole width: the control
    // goes in a row of its own under the artwork.
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final beside = _several && !quiet && !large;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Featured',
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: GestureDetector(
          onHorizontalDragStart: (_) => _dragged = 0,
          onHorizontalDragUpdate: (details) => _dragged += details.delta.dx,
          onHorizontalDragEnd: _dragEnd,
          child: LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _art(
                  context,
                  Size(box.maxWidth, FeaturedPager.artHeightFor(box.maxWidth)),
                ),
                if (quiet) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(alignment: Alignment.centerRight, child: _quietPager()),
                ] else if (_several && !beside) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(alignment: Alignment.centerRight, child: _control()),
                ] else
                  // Less the control's own room above the title.
                  SizedBox(height: beside ? AppSpacing.s : AppSpacing.slabY),
                _copy(context, inset: beside),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Duration get _artFade =>
      _reduceMotion ? FeaturedPager.quietFade : AppAnimation.imageCrossfade;

  Duration get _copyFade =>
      _reduceMotion ? FeaturedPager.quietFade : AppAnimation.textCrossfade;

  Widget _art(BuildContext context, Size size) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final page = widget.pages[_index];
    final still = _reduceMotion || !_several;
    return Semantics(
      button: true,
      label: page.label,
      onTap: () => _act(_Role.open),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _act(_Role.open),
        child: AnimatedContainer(
          duration: AppAnimation.light,
          curve: AppAnimation.standardCurve,
          height: size.height,
          decoration: BoxDecoration(
            color: room.raised,
            borderRadius: BorderRadius.circular(AppRadius.slab),
            boxShadow: AppElevation.hero(scheme, light: page.light?.light),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedBuilder(
            animation: _dwell,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                for (final (index, slide) in widget.pages.indexed)
                  AnimatedOpacity(
                    opacity: index == _index ? 1 : 0,
                    duration: _artFade,
                    curve: DesignTokens.motionImageXfadeCurve,
                    child: still
                        ? _FeaturedArt(slide.art, onDrawn: widget.onArtDrawn)
                        : _drifting(
                            index,
                            size,
                            _FeaturedArt(slide.art, onDrawn: widget.onArtDrawn),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [child] at the point of its drift: its seconds in front, alternating
  /// across [AppAnimation.kenBurns] on the drift's ease.
  Widget _drifting(int index, Size size, Widget child) {
    final seconds =
        _drift[index] + (index == _index ? _dwell.value * _dwellSeconds : 0);
    final period =
        AppAnimation.kenBurns.inMilliseconds / Duration.millisecondsPerSecond;
    final phase = (seconds % (2 * period)) / period;
    final there = DesignTokens.motionKenburnsCurve.transform(
      phase <= 1 ? phase : 2 - phase,
    );
    final scale =
        AppAnimation.kenBurnsFrom +
        (AppAnimation.kenBurnsTo - AppAnimation.kenBurnsFrom) * there;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..translateByDouble(
          -0.02 * size.width * there,
          -0.01 * size.height * there,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1),
      child: child,
    );
  }

  Widget _copy(BuildContext context, {required bool inset}) {
    final rise = _reduceMotion ? 0.0 : AppAnimation.textCrossfadeRise;
    return Stack(
      children: [
        Padding(
          // The control's 44 above the title, its line centred on the
          // title's first.
          padding: EdgeInsets.only(top: inset ? AppSpacing.sm : 0),
          child: Stack(
            children: [
              for (final (index, page) in widget.pages.indexed)
                IgnorePointer(
                  ignoring: index != _index,
                  child: ExcludeSemantics(
                    excluding: index != _index,
                    child: AnimatedOpacity(
                      opacity: index == _index ? 1 : 0,
                      duration: _copyFade,
                      curve: DesignTokens.motionTextXfadeCurve,
                      child: AnimatedContainer(
                        duration: _copyFade,
                        curve: DesignTokens.motionTextXfadeCurve,
                        transform: Matrix4.translationValues(
                          0,
                          index == _index ? 0 : rise,
                          0,
                        ),
                        child: _FeaturedCopy(
                          page: page,
                          inset: inset ? _FeaturedControl.width : 0,
                          onLead: () => _act(_Role.lead),
                          onSecond: () => _act(_Role.second),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (inset) Positioned(top: 0, right: 0, child: _control()),
      ],
    );
  }

  Widget _control() => _FeaturedControl(
    count: widget.pages.length,
    index: _index,
    paused: _paused,
    progress: _dwell,
    light: widget.pages[_index].light,
    onTap: _togglePause,
  );

  /// With a screen reader or Reduce Motion: a button per slide, then the
  /// control.
  Widget _quietPager() {
    final count = widget.pages.length;
    final room = CupolaRoom.of(context);
    final light = widget.pages[_index].light;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index++)
          Semantics(
            button: true,
            selected: index == _index,
            label: 'Show slide ${index + 1} of $count',
            onTap: () => _go(index),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _go(index),
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: _Pill(
                    on: index == _index,
                    fill: index == _index ? 1 : 0,
                    light: light,
                    room: room,
                  ),
                ),
              ),
            ),
          ),
        _PauseButton(
          paused: _paused,
          index: _index,
          count: count,
          onTap: _togglePause,
          child: Icon(
            _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 20,
            color: room.inkTertiary,
          ),
        ),
      ],
    );
  }
}

/// The title, its line and its two buttons.
class _FeaturedCopy extends StatelessWidget {
  const _FeaturedCopy({
    required this.page,
    required this.inset,
    required this.onLead,
    required this.onSecond,
  });

  final FeaturedPage page;

  /// The room the control takes beside the title.
  final double inset;

  final VoidCallback onLead;
  final VoidCallback onSecond;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final height = TextScaleMetrics.boxHeight(
      context,
      base: DesignTokens.sizeButtonL,
      textHeight: 20,
    );
    final lead = FilledButton.icon(
      onPressed: onLead,
      style: mediaLeadStyle(context, page.light),
      icon: page.lead.icon == null ? null : Icon(page.lead.icon, size: 20),
      label: Text(page.lead.label),
    );
    final second = page.second;
    final quiet = second == null
        ? null
        : OutlinedButton(
            onPressed: onSecond,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.standard,
              minimumSize: Size(104, height),
            ),
            child: Text(second.label),
          );
    // At a large reading size the two buttons go one under the other.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(right: inset),
          child: ExcludeSemantics(
            child: Text(
              page.title,
              // At a large reading size the title keeps its words whole.
              maxLines: stacked ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.feature.copyWith(color: room.ink),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        ExcludeSemantics(
          child: Text(
            page.line,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(color: room.inkSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.slabY),
        if (quiet == null)
          lead
        else if (stacked) ...[
          lead,
          const SizedBox(height: AppSpacing.sm),
          quiet,
        ] else
          Row(
            children: [
              Expanded(child: lead),
              const SizedBox(width: AppSpacing.row),
              quiet,
            ],
          ),
      ],
    );
  }
}

/// The pause control and the pager beside the title: one button, its glyph
/// and a pill per slide, the one in front filling as its time runs.
class _FeaturedControl extends StatelessWidget {
  const _FeaturedControl({
    required this.count,
    required this.index,
    required this.paused,
    required this.progress,
    required this.light,
    required this.onTap,
  });

  final int count;
  final int index;
  final bool paused;
  final Animation<double> progress;
  final TitleLight? light;
  final VoidCallback onTap;

  /// The room it takes beside the title.
  static const double width = 88;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return _PauseButton(
      paused: paused,
      index: index,
      count: count,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 16,
            color: room.inkTertiary,
          ),
          const SizedBox(width: AppSpacing.xs),
          AnimatedBuilder(
            animation: progress,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var at = 0; at < count; at++) ...[
                  if (at > 0) const SizedBox(width: AppSpacing.xs),
                  _Pill(
                    on: at == index,
                    fill: at == index ? progress.value : 0,
                    light: light,
                    room: room,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The control's one button: Pause while the slides move, Play while they
/// wait; 44 tall.
class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.paused,
    required this.index,
    required this.count,
    required this.onTap,
    required this.child,
  });

  final bool paused;
  final int index;
  final int count;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final label =
        '${paused ? 'Play' : 'Pause'} featured, ${index + 1} of $count';
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
  }
}

/// One slide's mark in the pager: a dot, or the long pill of the slide in
/// front, filled to [fill] with the slide's light.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.on,
    required this.fill,
    required this.light,
    required this.room,
  });

  final bool on;
  final double fill;
  final TitleLight? light;
  final CupolaRoom room;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lit = light == null
        ? room.ink
        : (dark ? light!.actionFill : light!.dayPrimary);
    return AnimatedContainer(
      duration: AppAnimation.emphasized,
      curve: AppAnimation.standardCurve,
      width: on ? 24 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: on ? room.fillTrack : room.inkDisabled,
        borderRadius: BorderRadius.circular(3),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fill.clamp(0.0, 1.0),
        heightFactor: 1,
        child: ColoredBox(color: lit),
      ),
    );
  }
}

/// A slide's artwork, decoded for its box, telling [onDrawn] once it is on
/// screen: its light is read from the same cache then.
class _FeaturedArt extends StatelessWidget {
  const _FeaturedArt(this.art, {this.onDrawn});

  final ImageSource art;
  final ValueChanged<String>? onDrawn;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final url = art.url;
    return ArtworkDecodeBox(
      builder: (context, decode) => CachedNetworkImage(
        imageUrl: url,
        httpHeaders: art.headers,
        cacheManager: pinnedImageCacheFor(url),
        memCacheWidth: decode.width,
        memCacheHeight: decode.height,
        fit: BoxFit.cover,
        imageBuilder: (context, image) {
          if (onDrawn case final told?) {
            WidgetsBinding.instance.addPostFrameCallback((_) => told(url));
          }
          return Image(image: image, fit: BoxFit.cover);
        },
        placeholder: (context, _) => ColoredBox(color: room.fillQuiet),
        errorWidget: (context, _, _) => ColoredBox(color: room.fillQuiet),
      ),
    );
  }
}

/// The art box and two lines, holding Featured's place while it is read.
class FeaturedSkeleton extends StatelessWidget {
  const FeaturedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: room.fillSkeleton,
        borderRadius: AppRadius.borderRadiusSm,
      ),
    );
    return Semantics(
      label: 'Loading featured',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: FeaturedPager.artHeightFor(box.maxWidth),
              decoration: BoxDecoration(
                color: room.fillSkeleton,
                borderRadius: BorderRadius.circular(AppRadius.slab),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            bar(200, 20),
            const SizedBox(height: AppSpacing.sm),
            bar(160, 12),
          ],
        ),
      ),
    );
  }
}
