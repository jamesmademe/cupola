@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/media_value_sheet.dart';
import 'package:cupola/core/widgets/media_search_popup_menu.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

void _noop() {}

/// The body of the quality profile sheet, which `showMediaValueSheet` opens on
/// the root navigator and so cannot be drawn inside a bounded scene: the same
/// [AppBottomSheet] header and [MediaValueOptionRow]s that it builds.
Widget _profileSheet() {
  const profiles = ['Any', 'SD', 'HD-720p', 'HD-1080p', 'Ultra-HD'];
  return AppBottomSheet(
    title: 'Quality profile',
    subtitle: 'Currently HD-1080p',
    icon: Icons.tune_rounded,
    accent: ServiceKey.radarr.accent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in profiles)
          MediaValueOptionRow(
            label: name,
            isSelected: name == 'HD-1080p',
            accent: ServiceKey.radarr.accent,
            onTap: _noop,
          ),
      ],
    ),
  );
}

/// The body of a long value sheet, the one-file episode picker of a manual
/// import: Grey's twenty-four episodes of a season under the search field,
/// drawn as [_profileSheet] is.
Widget _episodeSheet() {
  return AppBottomSheet(
    title: "Grey's.Anatomy.S21E17.1080p.WEB",
    subtitle: 'Currently none',
    icon: Icons.tune_rounded,
    bodyPadding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: MediaValueSearchList<int>(
      options: [
        for (var n = 1; n <= 24; n++)
          MediaDetailValueOption(value: n, label: 'E$n · Episode $n'),
      ],
      hint: 'Episode number or title',
      row: (option) => MediaValueOptionRow(
        label: option.label,
        isSelected: false,
        accent: null,
        onTap: _noop,
      ),
    ),
  );
}

/// Opens the [PopupMenuButton] inside [child] once it has laid out, on a
/// navigator local to the scene so the menu lands inside the scene's box.
class _OpenMenu extends StatelessWidget {
  const _OpenMenu({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      pageBuilder: (context, _, _) => _Opener(child: child),
    ),
  );
}

class _Opener extends StatefulWidget {
  const _Opener({required this.child});

  final Widget child;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void visit(Element element) {
        if (element is StatefulElement &&
            element.state is PopupMenuButtonState) {
          (element.state as PopupMenuButtonState).showButtonMenu();
          return;
        }
        element.visitChildren(visit);
      }

      if (mounted) (context as Element).visitChildren(visit);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topLeft, child: widget.child);
}

void main() {
  catalogCard(
    'MediaDetailActions',
    width: 776,
    scenes: [
      CatalogScene(
        'Quality profile sheet body (showMediaValueSheet) · the selected '
        'row in the primary ink (the page accent is the lamp)',
        (_) => _profileSheet(),
        width: 390,
      ),
      CatalogScene(
        'MediaSearchPopupMenu · idle, then searching (a 20pt, 2pt spinner)',
        (_) => Row(
          children: [
            MediaSearchPopupMenu(
              onAutoSearch: _noop,
              onInteractiveSearch: _noop,
            ),
            const SizedBox(width: 24),
            MediaSearchPopupMenu(
              onAutoSearch: _noop,
              onInteractiveSearch: _noop,
              isLoading: true,
            ),
          ],
        ),
      ),
      CatalogScene(
        'MediaSearchPopupMenu · open, the season and album search menu',
        (_) => const _OpenMenu(
          child: MediaSearchPopupMenu(
            onAutoSearch: _noop,
            onInteractiveSearch: _noop,
          ),
        ),
        width: 280,
        height: 150,
      ),
      CatalogScene(
        'Episode picker (showMediaValueSheet past 12 options) · the search '
        'field over the season',
        (_) => _episodeSheet(),
        width: 390,
        height: 900,
      ),
      CatalogScene(
        'Episode picker · 17 typed: a number is a whole number, E17 alone',
        (_) => _episodeSheet(),
        width: 390,
        height: 420,
        act: (tester, scene) async {
          await tester.enterText(
            find.descendant(of: scene, matching: find.byType(TextField)),
            '17',
          );
        },
      ),
      CatalogScene(
        'Text at 200% · the quality profile sheet body: the option rows keep '
        'their 48pt floor and wrap instead of clipping',
        (_) => _profileSheet(),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
