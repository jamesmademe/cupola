/// The lights the Home's titles lit it with, kept so a cold start is lit from
/// its first frame.
///
/// A title's light is read off its artwork once a slide has drawn it: a
/// decode and a quantisation that land half a second after the picture. At a
/// cold start the slide's lead action turned from ink to the title's colour
/// under the person's eyes, and the room with it. So the light is kept beside
/// the drawings, by the address of the artwork it was read from, and lights
/// the room until the picture is drawn and read again.
///
/// An address that carries a credential in its query is never kept, as a
/// drawing's pictures are not (`StoredImage.carriesCredential`). The lights
/// are valid for the connections the titles come from, as the drawings are,
/// and only the last [keptLightsCap] are kept.
library;

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// How many lights are kept: the slides of one Featured and the title Ready
/// to watch leads with, with room for the ones that just left.
const keptLightsCap = 8;

const _schema = 1;

String _key(Ref ref) => 'home.${ref.read(shellAudienceProvider).name}.lights';

/// The connections the lit titles come from: Featured's and Ready to
/// watch's.
String _validity(Ref ref) => homeLastKnownValidity(
  ref.read(currentSettingsProvider),
  {...HomeModule.featured.services, ...HomeModule.readyToWatch.services},
);

/// The kept lights, oldest first.
Map<String, Object?> _kept(Ref ref) {
  final data = ref
      .read(lastKnownStoreProvider)
      .read(_key(ref), validity: _validity(ref), schema: _schema)
      ?.data;
  return data is Map<String, Object?> ? data : const {};
}

/// The light kept for the artwork at [url], or null: none was read, or the
/// lamp lit it.
TitleLight? keptTitleLight(Ref ref, String url) =>
    _lightFromJson(_kept(ref)[url]);

/// Keeps [light] for the artwork at [url], the newest last and the oldest
/// dropped past [keptLightsCap]; null forgets it (artwork the lamp lights).
/// The same light already kept writes nothing.
void keepTitleLight(Ref ref, String url, TitleLight? light) {
  if (url.isEmpty || StoredImage.carriesCredential(url)) return;
  final kept = _kept(ref);
  if (_lightFromJson(kept[url]) == light) return;
  final next = <String, Object?>{
    for (final MapEntry(:key, :value) in kept.entries)
      if (key != url) key: value,
    if (light != null) url: _lightToJson(light),
  };
  while (next.length > keptLightsCap) {
    next.remove(next.keys.first);
  }
  ref
      .read(lastKnownStoreProvider)
      .write(
        _key(ref),
        validity: _validity(ref),
        schema: _schema,
        data: next,
        takenAt: ref.read(calendarClockProvider)(),
      );
}

Map<String, int> _lightToJson(TitleLight light) => {
  'light': light.light.toARGB32(),
  'actionFill': light.actionFill.toARGB32(),
  'actionInk': light.actionInk.toARGB32(),
  'dayPrimary': light.dayPrimary.toARGB32(),
};

TitleLight? _lightFromJson(Object? json) {
  if (json is! Map) return null;
  Color? color(String name) => switch (json[name]) {
    final int argb => Color(argb),
    _ => null,
  };
  final light = color('light');
  final actionFill = color('actionFill');
  final actionInk = color('actionInk');
  final dayPrimary = color('dayPrimary');
  if (light == null ||
      actionFill == null ||
      actionInk == null ||
      dayPrimary == null) {
    return null;
  }
  return TitleLight(
    light: light,
    actionFill: actionFill,
    actionInk: actionInk,
    dayPrimary: dayPrimary,
  );
}
