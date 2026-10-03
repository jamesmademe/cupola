import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/providers/provider_retry.dart';

/// The colours a title's artwork lights its room with (brand book, *The title
/// light*): derived, never picked.
@immutable
class TitleLight {
  const TitleLight({
    required this.light,
    required this.actionFill,
    required this.actionInk,
    required this.dayPrimary,
  });

  /// The light itself: the ambient wash, the poster and hero glow. HCT tone
  /// 68, chroma 16–48.
  final Color light;

  /// The tinted fill of the page's one lead action in the dark room: tone 82,
  /// chroma 12–36.
  final Color actionFill;

  /// The ink on [actionFill]: tone 12, chroma 4–16, about 10:1 on it.
  final Color actionInk;

  /// The day room's tinted primary, under white: tone 40, chroma 16–48.
  final Color dayPrimary;

  @override
  bool operator ==(Object other) =>
      other is TitleLight &&
      other.light == light &&
      other.actionFill == actionFill &&
      other.actionInk == actionInk &&
      other.dayPrimary == dayPrimary;

  @override
  int get hashCode => Object.hash(light, actionFill, actionInk, dayPrimary);
}

/// The side of the decode the light is read from: 64 px, as the brand book
/// says. A light is a hue, and a hue needs no detail.
const titleLightDecodeSize = 64;

/// The light of [pixels] (ARGB, one per pixel), or null for artwork with too
/// little chroma: that room is lit by the neutral lamp.
///
/// Quantised with Celebi to 128 colours, clusters darker than HCT tone 18 or
/// lighter than 92 dropped (the black ground and the lettering), the rest
/// scored by Material's `Score`, which keeps only colours of chroma 5 or more
/// that cover more than 1% of the picture. Pure and isolate-safe: the page
/// runs it through `compute`.
Future<TitleLight?> titleLightFromPixels(List<int> pixels) async {
  if (pixels.isEmpty) return null;
  final quantized = await QuantizerCelebi().quantize(pixels, 128);
  final kept = <int, int>{
    for (final entry in quantized.colorToCount.entries)
      if (Hct.fromInt(entry.key).tone case final tone
          when tone >= 18 && tone <= 92)
        entry.key: entry.value,
  };
  if (kept.isEmpty) return null;
  // Score answers its fallback when nothing qualifies: an impossible ARGB
  // (fully transparent) marks that, so it can never be taken for a colour.
  const none = 0x00000000;
  final best = Score.score(kept, desired: 1, fallbackColorARGB: none).first;
  if (best == none) return null;

  final source = Hct.fromInt(best);
  final hue = source.hue;
  Color at(double chroma, double minimum, double maximum, double tone) =>
      Color(Hct.from(hue, chroma.clamp(minimum, maximum), tone).toInt());
  return TitleLight(
    light: at(source.chroma, 16, 48, 68),
    actionFill: at(source.chroma, 12, 36, 82),
    actionInk: at(source.chroma, 4, 16, 12),
    dayPrimary: at(source.chroma, 16, 48, 40),
  );
}

/// The light of the artwork at [url], or null for artwork with too little
/// chroma.
///
/// The picture comes through the pinned image cache, the same file the page
/// shows; it is decoded at [titleLightDecodeSize] and read off the UI
/// isolate. A picture that cannot be fetched fails the provider, and the room
/// keeps the lamp.
final titleLightProvider = FutureProvider.autoDispose
    .family<TitleLight?, String>((ref, url) async {
      final cache = pinnedImageCacheFor(url) ?? DefaultCacheManager();
      final file = await cache.getSingleFile(url);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: titleLightDecodeSize,
        targetHeight: titleLightDecodeSize,
      );
      final frame = await codec.getNextFrame();
      final rgba = await frame.image.toByteData();
      frame.image.dispose();
      codec.dispose();
      if (rgba == null) return null;
      final pixels = <int>[
        for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
          if (rgba.getUint8(i + 3) == 0xFF)
            0xFF000000 |
                rgba.getUint8(i) << 16 |
                rgba.getUint8(i + 1) << 8 |
                rgba.getUint8(i + 2),
      ];
      return compute(titleLightFromPixels, pixels);
    }, retry: noProviderRetry);
