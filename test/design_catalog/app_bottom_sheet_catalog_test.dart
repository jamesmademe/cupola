@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/media_detail_value_row.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// The sheet as it stands open: the page under the modal barrier, and the
/// panel risen from the bottom edge. An open sheet is a route of its own and
/// paints above the page, so the scene draws the same panel in place.
Widget _open(Widget sheet, {double maxWidth = double.infinity}) => Builder(
  builder: (context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: Theme.of(context).colorScheme.surface),
      // `showModalBottomSheet`'s default barrier.
      const ColoredBox(color: Colors.black54),
      Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: sheet,
        ),
      ),
    ],
  ),
);

const _profiles = ['Any', 'HD-720p', 'HD-1080p', 'Ultra-HD'];

Widget _qualityPicker() => AppBottomSheet(
  title: 'Quality profile',
  subtitle: 'Currently HD-1080p',
  icon: Icons.tune_rounded,
  accent: ServiceKey.radarr.accent,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final profile in _profiles)
        MediaValueOptionRow(
          label: profile,
          isSelected: profile == 'HD-1080p',
          accent: ServiceKey.radarr.accent,
          onTap: () {},
        ),
    ],
  ),
);

/// qBittorrent's Add torrent form, as the caller builds it.
Widget _addTorrent() => AppBottomSheet(
  title: 'Add torrent',
  icon: Icons.add_link_rounded,
  accent: ServiceKey.qbittorrent.accent,
  child: Builder(
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextField(
          decoration: InputDecoration(
            labelText: 'Magnet / URL',
            hintText: 'magnet:?xt=urn:btih:...',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: const Text('Pick .torrent files'),
          onPressed: () {},
        ),
        const SizedBox(height: AppSpacing.md),
        const TextField(
          decoration: InputDecoration(labelText: 'Category (optional)'),
        ),
        const SizedBox(height: AppSpacing.md),
        const TextField(
          decoration: InputDecoration(labelText: 'Save path (optional)'),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          style: FilledButton.styleFrom(
            textStyle: Theme.of(
              context,
            ).textTheme.labelLarge!.weight(FontWeight.w600),
            minimumSize: const Size.fromHeight(46),
          ),
          onPressed: () {},
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18),
              SizedBox(width: 8),
              Text('Add torrent'),
            ],
          ),
        ),
      ],
    ),
  ),
);

const _releases = [
  'Nosferatu.1922.1080p.BluRay.x264',
  'Nosferatu.1922.720p.BluRay.x264',
  'Nosferatu.1922.Restored.1080p.WEB-DL.H264',
  'Nosferatu.1922.2160p.UHD.BluRay.x265',
  'Nosferatu.1922.480p.DVDRip.XviD',
  'Nosferatu.1922.1080p.BluRay.FLAC.x264',
  'Nosferatu.1922.Tinted.720p.WEB.H264',
];

/// What `showScrollable` builds: the panel in draggable mode, its body the
/// caller's list on the sheet's own controller.
class _ScrollableSheet extends StatefulWidget {
  const _ScrollableSheet();

  @override
  State<_ScrollableSheet> createState() => _ScrollableSheetState();
}

class _ScrollableSheetState extends State<_ScrollableSheet> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    // `initialSize: 0.6` of an 812pt phone.
    height: 487,
    child: AppBottomSheet(
      title: 'Interactive search',
      subtitle: 'Nosferatu (1922)',
      icon: Icons.manage_search_rounded,
      accent: ServiceKey.radarr.accent,
      showClose: true,
      bodyPadding: EdgeInsets.zero,
      scrollController: _controller,
      child: ListView(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: [
          for (final release in _releases)
            ListTile(
              title: Text(
                release,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Indexer · 2.1 GB · 48 seeders'),
            ),
        ],
      ),
    ),
  );
}

CatalogScene _scene(
  String caption,
  Widget Function() sheet, {
  double height = 420,
  double width = 390,
  CatalogPlatform platform = CatalogPlatform.phone,
  double maxWidth = double.infinity,
}) => CatalogScene(
  caption,
  (_) => _open(sheet(), maxWidth: maxWidth),
  width: width,
  height: height,
  platform: platform,
);

void main() {
  catalogCard(
    'AppBottomSheet',
    width: 880,
    scenes: [
      _scene(
        'AppBottomSheet.show · a picker with icon, accent and subtitle · the '
        'service\'s accent is the lamp: a soft glow behind the header, the '
        'tile a 14% lamp wash under an ink glyph',
        _qualityPicker,
        height: 440,
      ),
      _scene(
        'AppBottomSheet.show · qBittorrent\'s Add torrent form · the body '
        'scrolls inside a sheet capped at 92% of the screen',
        _addTorrent,
        height: 520,
      ),
      _scene(
        'AppBottomSheet.showScrollable · a list on the sheet\'s own controller, '
        'close button in the header',
        _ScrollableSheet.new,
        height: 560,
      ),
      _scene(
        'No title, no accent · handle and body only',
        () => const AppBottomSheet(
          child: Text(
            'Cupola couldn\'t reach Radarr, so this movie was not deleted.',
          ),
        ),
        height: 160,
      ),
      _scene(
        'showHandle: false · the header takes the handle\'s place with md above',
        () => AppBottomSheet(
          title: 'Series type',
          subtitle: 'How Sonarr reads episode numbers out of a release name',
          icon: Icons.tv_rounded,
          accent: ServiceKey.sonarr.accent,
          showHandle: false,
          child: const SizedBox(height: 48),
        ),
        height: 200,
      ),
      _scene(
        'Long title and subtitle · both stop at two lines',
        () => AppBottomSheet(
          title: 'Delete The Cabinet of Dr. Caligari and its files from Radarr',
          subtitle:
              'The Cabinet of Dr. Caligari (1920) · Das Cabinet des Dr. '
              'Caligari · restored edition from the 2014 tinted negative scan',
          icon: Icons.delete_outline_rounded,
          accent: ServiceKey.radarr.accent,
          showClose: true,
          child: const SizedBox(height: 48),
        ),
        height: 240,
      ),
      _scene(
        'On a desktop window · the modal sheet caps at 640pt wide, centred',
        _qualityPicker,
        width: 832,
        height: 440,
        maxWidth: 640,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
