@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/interactive_search_sheet.dart';
import 'package:cupola/core/widgets/release_list_widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

const _gb = 1024 * 1024 * 1024;

/// A release as Radarr's `/api/v3/release` returns it, cut to the fields the
/// row reads.
Map<String, dynamic> _release(
  String title, {
  required String quality,
  required String protocol,
  required int sizeGb100,
  required int ageDays,
  required String indexer,
  int score = 0,
  int? seeders,
  int? leechers,
  bool approved = true,
  List<String> rejections = const [],
  List<Map<String, dynamic>> customFormats = const [],
}) => {
  'guid': title,
  'indexerId': 1,
  'title': title,
  'indexer': indexer,
  'size': sizeGb100 * _gb ~/ 100,
  'ageMinutes': ageDays * 24 * 60,
  'protocol': protocol,
  'quality': {
    'quality': {'name': quality},
  },
  'customFormatScore': score,
  'customFormats': customFormats,
  'seeders': ?seeders,
  'leechers': ?leechers,
  'approved': approved,
  'rejections': rejections,
};

final _remux = _release(
  'Nosferatu.1922.2160p.UHD.BluRay.REMUX.HDR.TrueHD.7.1-GROUP',
  quality: 'Bluray-2160p',
  protocol: 'torrent',
  sizeGb100: 1860,
  ageDays: 412,
  indexer: 'Example Torrents',
  score: 1450,
  seeders: 142,
  leechers: 9,
  customFormats: [
    {'name': 'Remux Tier 01', 'score': 1300},
    {'name': 'HDR', 'score': 150},
  ],
);

final _usenet = _release(
  'Nosferatu.1922.1080p.BluRay.DD5.1.x265.10bit-GROUP',
  quality: 'Bluray-1080p',
  protocol: 'usenet',
  sizeGb100: 847,
  ageDays: 96,
  indexer: 'Example Usenet',
  approved: false,
);

final _rejected = _release(
  'Nosferatu.1922.1080p.WEBRip.x264.AAC-GROUP',
  quality: 'WEBRip-1080p',
  protocol: 'torrent',
  sizeGb100: 231,
  ageDays: 187,
  indexer: 'Example Indexer',
  score: -50,
  seeders: 0,
  leechers: 3,
  rejections: [
    'WEBRip-1080p is not wanted in profile',
    "Custom Formats LQ have score -50 below Movie's minimum 0",
  ],
  customFormats: [
    {'name': 'LQ', 'score': -50},
  ],
);

final _fewSeeders = _release(
  'Nosferatu.1922.720p.BluRay.x264-GROUP',
  quality: 'Bluray-720p',
  protocol: 'torrent',
  sizeGb100: 412,
  ageDays: 2300,
  indexer: 'Example Torrents',
  score: 150,
  seeders: 3,
  leechers: 1,
);

final _long = _release(
  'Nosferatu.Eine.Symphonie.des.Grauens.1922.Restored.Tinted.Edition.'
  '1080p.BluRay.FLAC.2.0.x264-GROUP',
  quality: 'Bluray-1080p',
  protocol: 'torrent',
  sizeGb100: 1120,
  ageDays: 31,
  indexer: 'Example Torrents with a Long Name',
  score: 0,
  seeders: 48,
  leechers: 2,
);

/// Opens the row's details once it has laid out, as a tap on the row does.
class _Expanded extends StatefulWidget {
  const _Expanded({required this.child});

  final Widget child;

  @override
  State<_Expanded> createState() => _ExpandedState();
}

class _ExpandedState extends State<_Expanded> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InkWell? row;
      void visit(Element element) {
        if (row != null) return;
        if (element.widget case final InkWell ink) {
          row = ink;
          return;
        }
        element.visitChildren(visit);
      }

      if (!mounted) return;
      (context as Element).visitChildren(visit);
      row?.onTap?.call();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void _noop() {}

Widget _sheet(List<dynamic> releases) {
  final controller = ScrollController();
  return AppBottomSheet(
    title: 'Releases',
    subtitle: 'Nosferatu (1922)',
    icon: Icons.travel_explore_rounded,
    accent: ServiceKey.radarr.accent,
    showClose: true,
    scrollController: controller,
    bodyPadding: EdgeInsets.zero,
    child: InteractiveSearchSheet(
      releases: releases,
      title: 'Nosferatu (1922)',
      onGrabRelease: (_, _) async {},
      scrollController: controller,
    ),
  );
}

void main() {
  catalogCard(
    'ReleaseRow',
    width: 768,
    scenes: [
      CatalogScene(
        'ReleaseListItem · approved, not approved, rejected · green, blue and '
        'amber rails; rejected also takes an amber border, never red',
        (_) => Column(
          children: [
            ReleaseListItem(release: _remux, onGrab: _noop),
            ReleaseListItem(release: _usenet, onGrab: _noop),
            ReleaseListItem(release: _rejected, onGrab: _noop),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'Peers · 0 seeders amber, under 5 blue, else green; a zero score '
        'reads neutral',
        (_) => Column(
          children: [
            ReleaseListItem(release: _fewSeeders, onGrab: _noop),
            ReleaseListItem(release: _long, onGrab: _noop),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'Grab · this row grabbing (spinner in the walked tone), then another '
        "row's grab in flight (6% fill, disabled)",
        (_) => Column(
          children: [
            ReleaseListItem(release: _remux, onGrab: null, isGrabbing: true),
            ReleaseListItem(release: _usenet, onGrab: null),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'Expanded, rejected · the full name with a copy button, custom '
        'formats and rejection reasons, all neutral',
        (_) => _Expanded(
          child: ReleaseListItem(release: _rejected, onGrab: _noop),
        ),
        width: 390,
      ),
      CatalogScene(
        'Expanded, approved · rewarded custom formats in green',
        (_) => _Expanded(
          child: ReleaseListItem(release: _remux, onGrab: _noop),
        ),
        width: 390,
      ),
      CatalogScene(
        'Expanded, no custom format data · the row says so rather than '
        'drawing an empty section',
        (_) => _Expanded(
          child: ReleaseListItem(release: _usenet, onGrab: _noop),
        ),
        width: 390,
      ),
      CatalogScene(
        'ScoreBadge +1450, 0, -50 · CustomFormatChip +150, -50 · InfoChip',
        (_) => const Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ScoreBadge(score: 1450),
            ScoreBadge(score: 0),
            ScoreBadge(score: -50),
            CustomFormatChip(name: 'HDR', score: 150),
            CustomFormatChip(name: 'LQ', score: -50),
            InfoChip(icon: Icons.storage_outlined, text: '18.6 GB'),
          ],
        ),
      ),
      CatalogScene(
        'InteractiveSearchSheet in AppBottomSheet · filter field, sort and '
        'filter chips, the count, rows sorted by CF score',
        (_) => _sheet([_usenet, _rejected, _remux, _fewSeeders]),
        width: 390,
        height: 760,
      ),
      CatalogScene(
        'InteractiveSearchSheet, no releases · the empty state',
        (_) => _sheet(const []),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'ReleaseListItem on the desktop · the same row in a wider sheet',
        (_) => Column(
          children: [
            ReleaseListItem(release: _remux, onGrab: _noop),
            ReleaseListItem(release: _rejected, onGrab: _noop),
          ],
        ),
        width: 640,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · approved, not approved and rejected rows, then the '
        'score and info chips, at twice the reading size',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReleaseListItem(release: _remux, onGrab: _noop),
            ReleaseListItem(release: _usenet, onGrab: _noop),
            ReleaseListItem(release: _rejected, onGrab: _noop),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ScoreBadge(score: 1450),
                ScoreBadge(score: -50),
                CustomFormatChip(name: 'HDR', score: 150),
                InfoChip(icon: Icons.storage_outlined, text: '18.6 GB'),
              ],
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · a rejected row expanded: the full name, the custom '
        'formats and the rejection reasons',
        (_) => _Expanded(
          child: ReleaseListItem(release: _rejected, onGrab: _noop),
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · InteractiveSearchSheet in AppBottomSheet: the filter '
        'field, the chips and the rows',
        (_) => _sheet([_usenet, _rejected, _remux, _fewSeeders]),
        width: 390,
        height: 1200,
        textScale: catalogTextScale,
      ),
    ],
  );
}
