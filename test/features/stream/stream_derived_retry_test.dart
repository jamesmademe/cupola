import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

DioException _refused(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  message: 'refused',
);

/// A media server that answers nothing. `noSuchMethod` stands in for the rest
/// of the surface: this is about how a failure travels, not about the client.
class _DarkStreamServer implements StreamServerClient {
  @override
  Future<List<StreamLibrary>> getLibraries() async => throw _refused('/Views');

  @override
  Future<List<StreamViewer>> getViewers() async => throw _refused('/Users');

  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => throw _refused('/Items/$itemId');

  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => throw _refused('/Items/$itemId/Children');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DarkPlex implements PlexClient {
  @override
  Future<PlexServerCapabilities> getCapabilities() async => throw _refused('/');

  @override
  Future<List<StreamLibrary>> getLibraries({CancelToken? cancelToken}) async =>
      throw _refused('/library/sections');

  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => throw _refused('/library/metadata/$itemId');

  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => throw _refused('/library/metadata/$itemId/children');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The sessions providers have carried `retry: noProviderRetry` since the
  // Stream board landed; every other read off the same client did not, and the
  // default retry holds a failed future through ten backing-off attempts. A
  // detail page opened against a server that has gone dark therefore sat on a
  // spinner for the better part of a minute before it could say so.
  test('a dark Jellyfin fails its derived reads at once', () async {
    final container = ProviderContainer(
      overrides: [
        jellyfinServerProvider.overrideWithValue(_DarkStreamServer()),
      ],
    );
    addTearDown(container.dispose);

    for (final future in [
      container.read(jellyfinLibrariesProvider.future),
      container.read(jellyfinViewersProvider.future),
      container.read(jellyfinItemProvider('42').future),
      container.read(jellyfinItemChildrenProvider('42').future),
    ]) {
      await expectLater(
        future.timeout(const Duration(milliseconds: 300)),
        throwsA(isA<DioException>()),
      );
    }
  });

  test('a dark Plex does the same', () async {
    final container = ProviderContainer(
      overrides: [plexClientProvider.overrideWithValue(_DarkPlex())],
    );
    addTearDown(container.dispose);

    for (final future in [
      container.read(plexCapabilitiesProvider.future),
      container.read(plexLibrariesProvider.future),
      container.read(plexItemProvider('42').future),
      container.read(plexChildrenProvider('42').future),
    ]) {
      await expectLater(
        future.timeout(const Duration(milliseconds: 300)),
        throwsA(isA<DioException>()),
      );
    }
  });
}
