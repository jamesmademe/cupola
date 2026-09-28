@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/media_prose_section.dart';

import 'catalog.dart';

const _overview =
    'Thomas Hutter, a young estate agent in the town of Wisborg, travels to '
    'a remote Carpathian castle to close a property sale with the reclusive '
    'Count Orlok. What he finds there convinces him too late that his host '
    'is no ordinary nobleman: Orlok is a vampire, and he has already booked '
    'passage to Wisborg aboard a merchant ship, carrying his coffins and a '
    'plague of rats below decks. As the ship drifts in with its crew dead and '
    "the town's death toll climbs, Hutter's wife Ellen reads of the one thing "
    "that can end a vampire's reign, and resolves to save the town herself, "
    'whatever it costs her.';

const _short =
    'A young projectionist who dreams of being a detective walks into the '
    'film he is showing and solves the case on screen.';

/// Presses the first [TextButton] below it once it has laid out, the way a
/// reader would — the expansion is the section's own state.
class _Pressed extends StatefulWidget {
  const _Pressed({required this.child});

  final Widget child;

  @override
  State<_Pressed> createState() => _PressedState();
}

class _PressedState extends State<_Pressed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      VoidCallback? press;
      void visit(Element element) {
        if (press != null) return;
        final widget = element.widget;
        if (widget is TextButton) {
          press = widget.onPressed;
          return;
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
      press?.call();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A slot arrives tight-width from the spine, so the scenes do too.
Widget _slot(double width, Widget child) =>
    SizedBox(width: width, child: child);

Widget _pair(List<Widget> children) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final (index, child) in children.indexed) ...[
      if (index > 0) const SizedBox(width: 32),
      child,
    ],
  ],
);

const _radarr = AppColors.radarr;
const _sonarr = AppColors.sonarr;

void main() {
  catalogCard(
    'MediaProseSection',
    width: 1100,
    scenes: [
      CatalogScene(
        'MediaProseSection(accent: radarr) · phone column, clamped at six '
        'lines, then expanded · Show more appears because the clamp bites, '
        'reads Show less once open, and draws in the page\'s accent walked '
        'against the surface',
        (_) => _pair([
          _slot(358, const MediaProseSection(text: _overview, accent: _radarr)),
          _slot(
            358,
            const _Pressed(
              child: MediaProseSection(text: _overview, accent: _radarr),
            ),
          ),
        ]),
      ),
      CatalogScene(
        'MediaProseSection · a two-line overview, then maxLines: 3 with no '
        'accent · no control when nothing is hidden; the clamp is the '
        'caller\'s to set; with no service owning the page the verb is primary',
        (_) => _pair([
          _slot(358, const MediaProseSection(text: _short)),
          _slot(358, const MediaProseSection(text: _overview, maxLines: 3)),
        ]),
      ),
      CatalogScene(
        'MediaProseSection · 1.5× reading size · bounded by lines, not by a '
        'height, so it grows downward',
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: _slot(358, const MediaProseSection(text: _overview)),
        ),
      ),
      CatalogScene(
        'MediaProseSection(accent: sonarr) · a 1000 wide track, expanded · '
        'the measure caps at 640, leading-aligned, however wide the slot',
        (_) => _slot(
          1000,
          const _Pressed(
            child: MediaProseSection(text: _overview, accent: _sonarr),
          ),
        ),
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
