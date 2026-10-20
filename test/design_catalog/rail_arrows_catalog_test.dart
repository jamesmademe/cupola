@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/rail_arrows.dart';
import 'package:cupola/core/widgets/section_header.dart';

import 'catalog.dart';

/// A rail of [count] posters under [header], scrolled to [at] (0 the start,
/// 1 the end) once it has laid out.
Widget _rail({
  required int count,
  double at = 0,
  required SectionHeader Function(Widget? arrows) header,
}) => RailArrows(
  builder: (context, controller, arrows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      header(arrows),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        height: 156,
        child: _ScrolledTo(
          at: at,
          child: ListView.separated(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: count,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.carouselGap),
            itemBuilder: (_, _) => SizedBox(
              width: 104,
              child: ContentCard(imageUrl: CatalogArt.poster, onTap: () {}),
            ),
          ),
        ),
      ),
    ],
  ),
);

/// Moves the rail above it to [at] of its extent after the first frame.
class _ScrolledTo extends StatefulWidget {
  const _ScrolledTo({required this.at, required this.child});

  final double at;
  final Widget child;

  @override
  State<_ScrolledTo> createState() => _ScrolledToState();
}

class _ScrolledToState extends State<_ScrolledTo> {
  @override
  void initState() {
    super.initState();
    if (widget.at == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = RailArrows.controllerOf(context);
      if (controller == null || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent * widget.at);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

SectionHeader _seeAll(Widget? arrows) =>
    SectionHeader(title: 'Trending', onTap: () {}, rail: arrows);

SectionHeader _linked(Widget? arrows) => SectionHeader(
  title: 'Recently added',
  showChevron: false,
  onTap: () {},
  trailing: const Text('Library'),
  rail: arrows,
);

void main() {
  const width = 560.0;

  catalogCard(
    'RailArrows',
    scenes: [
      CatalogScene(
        'RailArrows in a SectionHeader that opens the rest · at the start: '
        '‹ off, › on; the chevron steps in beside the title',
        (_) => _rail(count: 12, header: _seeAll),
        width: width,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Partway along · both on; a link (an Overview\'s Library) keeps its '
        'place before them',
        (_) => _rail(count: 12, at: 0.5, header: _linked),
        width: width,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'At the end · › off',
        (_) => _rail(count: 12, at: 1, header: _seeAll),
        width: width,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'A rail that fits the window · no arrows',
        (_) => _rail(count: 3, header: _seeAll),
        width: width,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'The phone, with no pointer · no arrows: a finger swipes',
        (_) => _rail(count: 12, header: _seeAll),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · the title grows to the heading\'s ceiling, the arrows '
        'keep their 44pt and the line',
        (_) => _rail(count: 12, header: _seeAll),
        width: width,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}
