@Tags(['catalog'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/import/data/manual_import_service.dart';
import 'package:cupola/features/import/presentation/manual_import_locate_screen.dart';
import 'package:cupola/features/import/presentation/manual_import_review_rows.dart';
import 'package:cupola/features/import/presentation/manual_import_review_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/fake_api_client.dart';
import 'catalog.dart';

/// Radarr's root folder, and the top of its server: what Locate lists before
/// anything is chosen.
List<dynamic> _rootFolders() => [
  {'id': 1, 'path': '/media/movies', 'accessible': true, 'freeSpace': 23e9},
];

Map<String, dynamic> _top() => {
  'parent': null,
  'directories': [
    for (final name in const ['config', 'downloads', 'media', 'tmp'])
      {'type': 'folder', 'name': name, 'path': '/$name/'},
  ],
  'files': <dynamic>[],
};

/// A folder of a feature and its sample, both matched to the movie.
List<dynamic> _featureAndSample() => [
  {
    'path':
        '/downloads/Past.Lives.2023.1080p.BluRay/Past.Lives.2023.1080p.BluRay.mkv',
    'name': 'Past.Lives.2023.1080p.BluRay',
    'size': 9800000000,
    'movie': {'id': 42, 'title': 'Past Lives', 'year': 2023},
    'quality': {
      'quality': {'id': 7, 'name': 'Bluray-1080p'},
    },
    'languages': [
      {'id': 1, 'name': 'English'},
    ],
  },
  {
    'path':
        '/downloads/Past.Lives.2023.1080p.BluRay/'
        'Past.Lives.2023.1080p.BluRay.sample.mkv',
    'name': 'Past.Lives.2023.1080p.BluRay.sample',
    'size': 42000000,
    'movie': {'id': 42, 'title': 'Past Lives', 'year': 2023},
    'quality': {
      'quality': {'id': 7, 'name': 'Bluray-1080p'},
    },
    'languages': [
      {'id': 1, 'name': 'English'},
    ],
    'rejections': [
      {'reason': 'Sample', 'type': 'permanent'},
    ],
  },
];

/// Answers by the endpoint asked, so every render of a scene (each theme,
/// each platform) reads the same server.
class _Radarr extends FakeApiClient {
  _Radarr({required this.folder, this.scan = const []});

  final Map<String, dynamic> folder;
  final List<dynamic> scan;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    final data = path.endsWith('/rootfolder')
        ? _rootFolders()
        : path.endsWith('/filesystem')
        ? folder
        : path.endsWith('/manualimport')
        ? scan
        : const <dynamic>[];
    return Response(
      data: data,
      requestOptions: RequestOptions(path: path),
    );
  }
}

List<Override> _radarr(_Radarr client) => [
  manualImportServiceProvider(ServiceKey.radarr).overrideWith(
    (ref) => ManualImportService(client: client, service: ServiceKey.radarr),
  ),
];

const _empty = <String, dynamic>{
  'parent': null,
  'directories': <dynamic>[],
  'files': <dynamic>[],
};

CatalogScene _locate(String caption, {double textScale = 1}) => CatalogScene(
  caption,
  (_) => const ManualImportLocateScreen(service: ServiceKey.radarr),
  width: 390,
  height: 844,
  textScale: textScale,
  overrides: _radarr(_Radarr(folder: _top())),
);

void main() {
  catalogCard(
    'ManualImport',
    scenes: [
      _locate(
        'ManualImportLocateScreen() · as it opens, with no path: the server\'s '
        'top folder to browse, and the primary',
      ),
      _locate(
        'ManualImportLocateScreen() · as it opens, at 200%',
        textScale: 2,
      ),
      CatalogScene(
        'ManualImportReviewScreen() · a feature and its sample, as the scan '
        'leaves them',
        (_) => const ManualImportReviewScreen(
          service: ServiceKey.radarr,
          initialPath: '/downloads/Past.Lives.2023.1080p.BluRay',
        ),
        width: 390,
        height: 844,
        overrides: _radarr(_Radarr(folder: _empty, scan: _featureAndSample())),
      ),
      CatalogScene(
        'ManualImportReviewScreen() · the feature unticked, then Select all '
        'ready files',
        (_) => const ManualImportReviewScreen(
          service: ServiceKey.radarr,
          initialPath: '/downloads/Past.Lives.2023.1080p.BluRay',
        ),
        width: 390,
        height: 844,
        overrides: _radarr(_Radarr(folder: _empty, scan: _featureAndSample())),
        act: (tester, scene) async {
          // The feature's own row, not the title's header: unticked, so the
          // selection is empty but for what Select all will add.
          final feature = find.descendant(
            of: scene,
            matching: find.byWidgetPredicate(
              (widget) => widget is MatchedFileRow && !widget.item.isSample,
            ),
          );
          await tester.tap(
            find.descendant(of: feature, matching: find.byType(Checkbox)),
          );
          await tester.pump();
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.byTooltip('Select all ready files'),
            ),
          );
          await tester.pump();
        },
      ),
    ],
  );
}
