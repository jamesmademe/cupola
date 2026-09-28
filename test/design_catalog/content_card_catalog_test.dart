@Tags(['catalog'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client;

import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';

import 'catalog.dart';

/// On the catalog's pinned origin with no file behind it: the load fails.
const _missing = 'https://art.catalog/missing.jpg';

/// On an origin whose cache never answers, so the card holds its loading
/// frame. Served by [_servePending].
const _pending = 'https://pending.catalog/poster.jpg';

/// A cache that never answers: the image stays on its placeholder.
class _PendingCacheManager implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => StreamController<FileResponse>().stream;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _NoTransport implements Client {
  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Pins [_pending]'s origin beside the catalog's and routes it to
/// [_PendingCacheManager]. Runs inside the render, after the catalog has
/// installed its own seam, and the catalog's teardown resets both.
void _servePending() {
  if (CertTrustRegistry.pinFor(_pending) != null) return;
  CertTrustRegistry.update(const {
    'https://art.catalog:443': 'catalog',
    'https://pending.catalog:443': 'pending',
  });
  final served = pinnedImageCacheBuilder;
  pinnedImageCacheBuilder =
      ({
        required cacheKey,
        required fingerprint,
        required host,
        required port,
      }) => host == 'pending.catalog'
      ? (manager: _PendingCacheManager(), transport: _NoTransport())
      : served(
          cacheKey: cacheKey,
          fingerprint: fingerprint,
          host: host,
          port: port,
        );
}

const _stalled = StatusBadge(
  info: MediaStatusInfo(pipeline: MediaPipeline.stalled, progress: 0.43),
  compact: true,
);

Widget _cell(Widget card) => SizedBox(width: 130, height: 195, child: card);

void main() {
  catalogCard(
    'ContentCard',
    scenes: [
      CatalogScene(
        'ContentCard(badge:) · artwork with compact stalled and downloading '
        'badges, then an iconOnly dot · top-right over a shadow-ink radial',
        (_) => Wrap(
          spacing: 16,
          children: [
            _cell(
              const ContentCard(imageUrl: CatalogArt.poster, badge: _stalled),
            ),
            _cell(
              const ContentCard(
                imageUrl: CatalogArt.poster,
                badge: StatusBadge(
                  info: MediaStatusInfo(
                    pipeline: MediaPipeline.downloading,
                    progress: 0.42,
                  ),
                  compact: true,
                ),
              ),
            ),
            _cell(
              const ContentCard(
                imageUrl: CatalogArt.poster,
                badge: StatusBadge(
                  info: MediaStatusInfo(
                    availability: MediaAvailability.available,
                  ),
                  compact: true,
                  iconOnly: true,
                ),
              ),
            ),
          ],
        ),
      ),
      CatalogScene(
        'ContentCard() · artwork alone, then with onTap · radius-md, level-2, '
        'BoxFit.cover; onTap adds PressableScale and nothing visible',
        (_) => Wrap(
          spacing: 16,
          children: [
            _cell(const ContentCard(imageUrl: CatalogArt.poster)),
            _cell(ContentCard(imageUrl: CatalogArt.poster, onTap: () {})),
          ],
        ),
      ),
      CatalogScene(
        'ContentCard() · loading, no URL, failed load · shimmer, then '
        'the plate with movie_outlined, then the plate with '
        'broken_image_outlined — MediaPosterCard\'s well in both themes, '
        'glyph 32',
        (_) {
          _servePending();
          return Wrap(
            spacing: 16,
            children: [
              _cell(const ContentCard(imageUrl: _pending)),
              _cell(const ContentCard(imageUrl: null)),
              _cell(const ContentCard(imageUrl: _missing)),
            ],
          );
        },
      ),
      CatalogScene(
        'ContentCard(badge:) · no URL and failed load with a badge · the '
        'corner radial over a placeholder instead of artwork, fading out '
        'inside the card with no edge',
        (_) => Wrap(
          spacing: 16,
          children: [
            _cell(
              const ContentCard(
                imageUrl: null,
                badge: StatusBadge(
                  info: MediaStatusInfo(
                    availability: MediaAvailability.missing,
                  ),
                  compact: true,
                ),
              ),
            ),
            _cell(const ContentCard(imageUrl: _missing, badge: _stalled)),
          ],
        ),
      ),
    ],
  );
}
