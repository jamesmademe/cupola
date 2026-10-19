import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/title_light.dart';

/// A poster that glows with its own light (brand book, `shadow.poster`): the
/// light of its artwork, read once the poster has drawn its picture, so it
/// comes from the cache the picture filled; until then, and for a picture
/// behind a key, the lamp.
///
/// For a rail's few posters, never a grid's hundreds: each light is one more
/// small read of the picture off the UI isolate.
class PosterGlow extends StatelessWidget {
  const PosterGlow({super.key, required this.url, required this.builder});

  /// The poster's picture, or null for none. Only a public one is read.
  final String? url;

  /// The poster, given its light (null for the lamp) and what to call once
  /// its picture is drawn (null where nothing reads lights).
  final Widget Function(BuildContext context, Color? light, VoidCallback? drawn)
  builder;

  @override
  Widget build(BuildContext context) {
    // A poster drawn outside the app's providers (a preview, a widget on its
    // own) has nothing to read a light with, and glows with the lamp.
    final scoped =
        context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() !=
        null;
    if (!scoped) return builder(context, null, null);
    return _LitPoster(url: url, builder: builder);
  }
}

class _LitPoster extends ConsumerStatefulWidget {
  const _LitPoster({required this.url, required this.builder});

  final String? url;
  final Widget Function(BuildContext, Color?, VoidCallback?) builder;

  @override
  ConsumerState<_LitPoster> createState() => _PosterGlowState();
}

class _PosterGlowState extends ConsumerState<_LitPoster> {
  String? _drawn;

  void _onDrawn() {
    final url = widget.url;
    if (url == null || _drawn == url) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.url == url) setState(() => _drawn = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final light = url != null && url == _drawn
        ? ref.watch(titleLightProvider(url)).value?.light
        : null;
    return widget.builder(context, light, _onDrawn);
  }
}
