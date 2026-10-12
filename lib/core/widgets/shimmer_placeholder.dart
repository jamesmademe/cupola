import 'package:flutter/material.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/theme.dart';

/// A shimmer loading placeholder effect following Material Design 3.
///
/// Use this widget to show loading states for cards, lists, and other content.
class ShimmerPlaceholder extends StatefulWidget {
  /// Width of the placeholder (null for full width)
  final double? width;

  /// Height of the placeholder
  final double height;

  /// Border radius of the placeholder
  final BorderRadius? borderRadius;

  /// Whether to show as a circle
  final bool isCircle;

  const ShimmerPlaceholder({
    super.key,
    this.width,
    required this.height,
    this.borderRadius,
    this.isCircle = false,
  });

  /// Creates a card-shaped shimmer placeholder
  ShimmerPlaceholder.card({super.key, this.width, required this.height})
    : borderRadius = AppRadius.borderRadiusMd,
      isCircle = false;

  /// Creates a text line shimmer placeholder
  factory ShimmerPlaceholder.text({
    Key? key,
    double? width,
    double height = 14,
  }) {
    return ShimmerPlaceholder(
      key: key,
      width: width,
      height: height,
      borderRadius: AppRadius.borderRadiusXs,
    );
  }

  /// Creates a circular shimmer placeholder
  const ShimmerPlaceholder.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = null,
      isCircle = true;

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimation.shimmerDuration,
    )..repeat();

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // An alpha of the room's ink, and a brighter band: the block reads on the
    // ground, a slab or a lit header, and the sweep passes as light. It was
    // two opaque surface roles, the dark room's highlight darker than its
    // base (a shadow sweeping) and the day room's base 1.01:1 on the ground.
    final room = CupolaRoom.of(context);
    final baseColor = room.fillSkeleton;
    final highlightColor = room.fillSkeletonGlint;

    // Reduce Motion: this is an indefinitely repeating sweep, the single most
    // persistent animation in the app. Fall back to the flat base colour, which
    // still reads as "loading" against the surrounding surfaces.
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_controller.isAnimating) _controller.stop();
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.isCircle ? null : widget.borderRadius,
          color: baseColor,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle ? null : widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
        );
      },
    );
  }
}

/// A skeleton loading view for a list of items
class ShimmerList extends StatelessWidget {
  /// Number of shimmer items to show
  final int itemCount;

  /// Height of each shimmer item
  final double itemHeight;

  /// Spacing between items
  final double spacing;

  const ShimmerList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 72,
    this.spacing = 8,
  }) : _scrolls = false;

  /// The same skeleton standing on its own as a whole page.
  ///
  /// The default constructor shrink-wraps and refuses to scroll so it can be
  /// nested inside another scroll view. A skeleton that *is* the page needs the
  /// opposite: given a bounded box shorter than six 72pt rows, which is any
  /// phone once a filter bar is above it: a shrink-wrapped column overflows,
  /// where a scroll view simply clips. Two screens had written their own copy
  /// of this class to get that, byte for byte.
  const ShimmerList.page({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 72,
    this.spacing = 8,
  }) : _scrolls = true;

  final bool _scrolls;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Non-scrolling and shrink-wrapped so the skeleton can be nested inside
      // another scroll view (e.g. a loading state inside a ListView) without a
      // "viewport given unbounded height" error.
      physics: _scrolls ? null : const NeverScrollableScrollPhysics(),
      shrinkWrap: !_scrolls,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (context, index) => SizedBox(height: spacing),
      itemBuilder: (context, index) =>
          ShimmerPlaceholder.card(height: itemHeight),
    );
  }
}

/// A skeleton loading view for a grid of items
class ShimmerGrid extends StatelessWidget {
  /// Number of shimmer items to show
  final int itemCount;

  /// Number of columns
  final int crossAxisCount;

  const ShimmerGrid({super.key, this.itemCount = 9, this.crossAxisCount = 3});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) =>
          ShimmerPlaceholder.card(height: double.infinity),
    );
  }
}
