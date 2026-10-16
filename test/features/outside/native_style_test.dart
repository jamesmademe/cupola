import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// The widgets' colours and type are the app's, read from the live theme.
///
/// A widget cannot run Dart, and what the app paints is not in the token JSON
/// alone: each tone is walked for contrast against its ground at run time
/// (`statusToneColor`), and the roles are built from variable-font axes by
/// `AppTheme`. So this test builds both rooms, renders what the extension
/// needs as `OutsideStyle.swift`, and fails when the file is not what the
/// theme says. A change to a token, a tone or a role cannot reach the app
/// without reaching the widgets: regenerate with
///
///     UPDATE_NATIVE_STYLE=1 flutter test test/features/outside/native_style_test.dart
const _swiftPath = 'ios/CupolaWidgets/OutsideStyle.swift';
const _testPath = 'test/features/outside/native_style_test.dart';

/// A scrim over artwork is the same in both rooms: the picture is dark or
/// light whatever room the phone is in, so the words over it never follow the
/// room. These are the approved board's own bytes (T3 board: `_onArt`,
/// `_onArtDim`, and the `0A0A0D` foot of `_ArtPlate`). The scrim is the dark
/// room's own ground, so a tone over it is the dark room's tone, already
/// walked for that ground (asserted below).
const _onArt = Color(0xFFF7F6F2);
const _onArtDim = Color(0xB8FFFFFF);
const _scrimClear = Color(0x000A0A0D);
const _scrimFoot = Color(0xE60A0A0D);

/// One type role as the native side needs it: everything `UIFontDescriptor`
/// takes, and the line and tracking a `Text` takes.
typedef _Role = ({
  String family,
  double size,
  double lineHeight,
  double tracking,
  List<(String, double)> axes,
  bool tabular,
});

typedef _Room = ({
  Color ground,
  Color ink,
  Color dim,
  Color track,
  Color green,
  Color amber,
  Color blue,
  Color neutral,
});

_Role _roleOf(TextStyle style) {
  final variations = <String, double>{
    for (final variation in style.fontVariations ?? const <FontVariation>[])
      variation.axis: variation.value,
  };
  // The axes the faces have, in a fixed order, then anything else a role may
  // one day name: an axis that is dropped here is a drawing that drifts.
  const known = ['wght', 'wdth', 'opsz'];
  final axes = <(String, double)>[
    for (final tag in known)
      if (variations[tag] != null) (tag, variations[tag]!),
    for (final tag in (variations.keys.toList()..sort()))
      if (!known.contains(tag)) (tag, variations[tag]!),
  ];
  expect(variations['wght'], isNotNull, reason: 'a role names its weight axis');
  return (
    family: style.fontFamily!,
    size: style.fontSize!,
    lineHeight: style.height!,
    tracking: style.letterSpacing ?? 0,
    axes: axes,
    tabular:
        style.fontFeatures?.any(
          (feature) => feature.feature == 'tnum' && feature.value == 1,
        ) ??
        false,
  );
}

Map<String, _Role> _rolesOf(ThemeData theme) {
  final text = theme.textTheme;
  return {
    'label': _roleOf(text.labelMedium!),
    'title': _roleOf(text.titleSmall!.weight(FontWeight.w600)),
    'line': _roleOf(text.bodySmall!),
    'data': _roleOf(AppTheme.data(theme.brightness)),
    'figureHero': _roleOf(AppType.figureHero),
    'figureSmall': _roleOf(AppType.figureSmall),
  };
}

_Room _roomOf(ThemeData theme) {
  final scheme = theme.colorScheme;
  final ground = scheme.surface;
  return (
    ground: ground,
    ink: scheme.onSurface,
    dim: theme.extension<CupolaThemeColors>()!.dimText,
    track: scheme.onSurface.withValues(alpha: 0.12),
    green: statusToneColor(scheme, StatusTone.success, surface: ground),
    amber: statusToneColor(scheme, StatusTone.warning, surface: ground),
    blue: statusToneColor(scheme, StatusTone.info, surface: ground),
    neutral: statusToneColor(scheme, StatusTone.neutral),
  );
}

String _number(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  final fixed = value.toStringAsFixed(4);
  final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

String _byte(double channel) => (channel * 255).round().toString();

String _color(Color color) =>
    'Color(.sRGB, red: ${_byte(color.r)} / 255, green: ${_byte(color.g)} / 255, '
    'blue: ${_byte(color.b)} / 255, opacity: ${_number(color.a)})';

String _roomSource(String name, _Room room) {
  final fields = <String, Color>{
    'ground': room.ground,
    'ink': room.ink,
    'dim': room.dim,
    'track': room.track,
    'green': room.green,
    'amber': room.amber,
    'blue': room.blue,
    'neutral': room.neutral,
  };
  return [
    '  static let $name = OutsideRoom(',
    for (final MapEntry(:key, :value) in fields.entries)
      '    $key: ${_color(value)},',
    '  )',
  ].join('\n');
}

String _roleSource(String name, _Role role) {
  final axes = role.axes
      .map((axis) => 'OutsideAxis("${axis.$1}", ${_number(axis.$2)})')
      .join(', ');
  return [
    '  static let $name = OutsideRole(',
    '    family: "${role.family}",',
    '    size: ${_number(role.size)},',
    '    lineHeight: ${_number(role.lineHeight)},',
    '    tracking: ${_number(role.tracking)},',
    '    axes: [$axes],',
    '    tabular: ${role.tabular}',
    '  )',
  ].join('\n');
}

/// `OutsideStyle.swift` as the live theme says it.
String renderNativeStyle() {
  final dark = AppTheme.darkTheme();
  final light = AppTheme.lightTheme();
  final darkRoles = _rolesOf(dark);
  final lightRoles = _rolesOf(light);
  // One drawing in both rooms: only colour follows the room, so the roles are
  // emitted once, and a role that ever differs between rooms must be a
  // decision of this test, not a silent pick of one.
  for (final name in darkRoles.keys) {
    expect(
      _roleSource(name, lightRoles[name]!),
      _roleSource(name, darkRoles[name]!),
      reason: 'the "$name" role differs between the rooms',
    );
  }
  final darkRoom = _roomOf(dark);
  final lightRoom = _roomOf(light);
  expect(
    darkRoom.ground,
    _scrimFoot.withValues(alpha: 1),
    reason: 'the scrim is the dark ground: a tone over it is the dark tone',
  );
  for (final (room, colors) in [('dark', darkRoom), ('light', lightRoom)]) {
    for (final color in [
      colors.ground,
      colors.ink,
      colors.dim,
      colors.green,
      colors.amber,
      colors.blue,
      colors.neutral,
    ]) {
      expect(color.a, 1.0, reason: 'a $room colour is opaque');
    }
  }

  final b = StringBuffer()
    ..writeln(
      '// Generated by test/features/outside/native_style_test.dart. Do not edit.',
    )
    ..writeln('// Regenerate: UPDATE_NATIVE_STYLE=1 flutter test $_testPath')
    ..writeln()
    ..writeln('import SwiftUI')
    ..writeln()
    ..writeln('/// The colours of each room, as the app paints them: the tones')
    ..writeln(
      '/// are already walked for contrast against that room\'s ground.',
    )
    ..writeln('extension OutsideRoom {')
    ..writeln(_roomSource('dark', darkRoom))
    ..writeln()
    ..writeln(_roomSource('light', lightRoom))
    ..writeln('}')
    ..writeln()
    ..writeln(
      '/// The type roles the widgets draw with. The same in both rooms:',
    )
    ..writeln('/// only colour follows the room.')
    ..writeln('extension OutsideRole {');
  final roles = darkRoles.entries.toList();
  for (var i = 0; i < roles.length; i++) {
    b.writeln(_roleSource(roles[i].key, roles[i].value));
    if (i != roles.length - 1) b.writeln();
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('enum OutsideStyle {')
    ..writeln(
      '  /// Words over artwork, and the scrim that darkens its foot. The',
    )
    ..writeln(
      '  /// same in both rooms: a picture is dark or light whatever room the',
    )
    ..writeln(
      '  /// phone is in, so the words over it never follow the room. A tone',
    )
    ..writeln(
      '  /// over the scrim is the dark room\'s: the scrim is its ground.',
    )
    ..writeln('  static let onArt = ${_color(_onArt)}')
    ..writeln('  static let onArtDim = ${_color(_onArtDim)}')
    ..writeln('  static let scrimClear = ${_color(_scrimClear)}')
    ..writeln('  static let scrimFoot = ${_color(_scrimFoot)}')
    ..writeln()
    ..writeln(
      '  static let posterRadius: CGFloat = ${_number(AppRadius.poster)}',
    )
    ..writeln(
      '  static let tinyPosterRadius: CGFloat = ${_number(AppRadius.xs)}',
    )
    ..writeln()
    ..writeln('  static let spaceXxs: CGFloat = ${_number(AppSpacing.xxs)}')
    ..writeln('  static let spaceXs: CGFloat = ${_number(AppSpacing.xs)}')
    ..writeln('  static let spaceS: CGFloat = ${_number(AppSpacing.s)}')
    ..writeln('  static let spaceSm: CGFloat = ${_number(AppSpacing.sm)}')
    ..writeln('  static let spaceRow: CGFloat = ${_number(AppSpacing.row)}')
    ..writeln('  static let spaceSlabY: CGFloat = ${_number(AppSpacing.slabY)}')
    ..writeln('}');
  return b.toString();
}

void main() {
  test('OutsideStyle.swift is what the live theme paints', () {
    final rendered = renderNativeStyle();
    final file = File(_swiftPath);
    if (Platform.environment['UPDATE_NATIVE_STYLE'] == '1') {
      file.writeAsStringSync(rendered);
      return;
    }
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$_swiftPath is missing: run UPDATE_NATIVE_STYLE=1 flutter test '
          '$_testPath',
    );
    if (file.readAsStringSync() != rendered) {
      fail(
        '$_swiftPath is not what the theme paints. A token, a tone or a '
        'type role changed: regenerate it with\n'
        '  UPDATE_NATIVE_STYLE=1 flutter test $_testPath',
      );
    }
  });

  test('the file asks to be regenerated, not edited', () {
    expect(
      renderNativeStyle().split('\n').first,
      '// Generated by $_testPath. Do not edit.',
    );
  });

  test('no em dash reaches the extension', () {
    expect(renderNativeStyle(), isNot(contains(String.fromCharCode(0x2014))));
  });
}
