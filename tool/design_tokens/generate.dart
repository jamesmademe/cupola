/// Generates the app's design-token constants from `design/tokens/`.
///
/// The token sets under `design/tokens/` are the one editable source of the
/// design tokens, in the W3C Design Tokens format. This script reads them,
/// resolves their aliases, validates them, and writes two files that are never
/// edited by hand:
///
/// - `lib/core/generated/design_tokens.g.dart`, the typed Dart constants the
///   app's token classes read their values from;
/// - `design/system/tokens.json`, a flat listing of the same values for the
///   design-system reference.
///
/// ```sh
/// dart run tool/design_tokens/generate.dart          # write both outputs
/// dart run tool/design_tokens/generate.dart --check  # exit 1 if stale
/// ```
///
/// Pure Dart on purpose — `dart:io` and `dart:convert` only — so it runs
/// without a Flutter toolchain and adds nothing to the dependency graph.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Where the token sets live, relative to the package root.
const String tokensDirPath = 'design/tokens';

/// The generated Dart constants.
const String dartOutputPath = 'lib/core/generated/design_tokens.g.dart';

/// The generated design-system listing.
const String systemOutputPath = 'design/system/tokens.json';

void main(List<String> args) {
  final check = args.contains('--check');
  final TokenOutputs outputs;
  try {
    outputs = generate(loadTokenSource(Directory(tokensDirPath)));
  } on TokenValidationError catch (error) {
    stderr.writeln(error);
    exitCode = 1;
    return;
  }

  final targets = <String, String>{
    dartOutputPath: outputs.dart,
    systemOutputPath: outputs.systemJson,
  };

  if (check) {
    final stale = [
      for (final MapEntry(key: path, value: content) in targets.entries)
        if (!File(path).existsSync() ||
            File(path).readAsStringSync() != content)
          path,
    ];
    if (stale.isEmpty) {
      stdout.writeln('Design tokens are up to date.');
      return;
    }
    stderr.writeln(
      'Stale generated design tokens: ${stale.join(', ')}.\n'
      'Run `dart run tool/design_tokens/generate.dart` and commit the result.',
    );
    exitCode = 1;
    return;
  }

  for (final MapEntry(key: path, value: content) in targets.entries) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    stdout.writeln('Wrote $path');
  }
}

// ---------------------------------------------------------------------------
// Source model
// ---------------------------------------------------------------------------

/// Every problem found in the token sets, reported together.
class TokenValidationError implements Exception {
  TokenValidationError(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'Invalid design tokens (${problems.length}):\n'
      '${problems.map((problem) => '  - $problem').join('\n')}';
}

/// One theme as the theme configuration declares it.
class ThemeConfig {
  const ThemeConfig({
    required this.id,
    required this.name,
    required this.selectedTokenSets,
  });

  factory ThemeConfig.fromJson(Map<String, Object?> json) => ThemeConfig(
    id: '${json['id']}',
    name: '${json['name']}',
    selectedTokenSets: {
      for (final MapEntry(:key, :value)
          in ((json['selectedTokenSets'] as Map?) ?? const {}).entries)
        '$key': '$value',
    },
  );

  final String id;
  final String name;

  /// Set name to `source` (shared base), `enabled` (this theme's own set) or
  /// `disabled`.
  final Map<String, String> selectedTokenSets;
}

/// The parsed token sets plus the configuration that ties them into themes.
class TokenSource {
  const TokenSource({
    required this.sets,
    required this.setOrder,
    required this.themes,
  });

  /// Set name (its path under the tokens folder, without `.json`) to content.
  final Map<String, Object?> sets;

  /// The order the sets are listed in, from the metadata file.
  final List<String> setOrder;

  final List<ThemeConfig> themes;
}

/// Reads every set, the theme configuration and the metadata from [dir].
///
/// A set is any `.json` file below [dir] whose name does not start with `$`;
/// its name is its path relative to [dir] without the extension, so
/// `theme/dark.json` is the set `theme/dark`.
TokenSource loadTokenSource(Directory dir) {
  Object? readJson(File file) {
    try {
      return jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw TokenValidationError([
        '${file.path} is not valid JSON: ${error.message}',
      ]);
    }
  }

  final sets = <String, Object?>{};
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final relative = file.path
        .substring(dir.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (relative.split('/').last.startsWith(r'$')) continue;
    sets[relative.substring(0, relative.length - '.json'.length)] = readJson(
      file,
    );
  }

  final metadataFile = File('${dir.path}/\$metadata.json');
  final metadata = metadataFile.existsSync()
      ? readJson(metadataFile)
      : const <String, Object?>{};
  final setOrder = [
    for (final name
        in (metadata as Map?)?['tokenSetOrder'] as List? ?? const [])
      '$name',
  ];

  final themesFile = File('${dir.path}/\$themes.json');
  final themesJson = themesFile.existsSync() ? readJson(themesFile) : const [];
  return TokenSource(
    sets: sets,
    setOrder: setOrder,
    themes: [
      for (final theme in themesJson as List)
        ThemeConfig.fromJson((theme as Map).cast<String, Object?>()),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

/// The value types the generator understands, after normalisation.
enum TokenType { color, dimension, number, fontWeight, fontFamily, duration }

/// Accepted `$type` spellings. The format's own names come first; the rest are
/// the plural and property-specific names some editors write back, mapped to
/// the format type they mean so a round trip through one does not break the
/// build.
const Map<String, TokenType> _typeNames = {
  'color': TokenType.color,
  'dimension': TokenType.dimension,
  'number': TokenType.number,
  'fontWeight': TokenType.fontWeight,
  'fontFamily': TokenType.fontFamily,
  'duration': TokenType.duration,
  'spacing': TokenType.dimension,
  'sizing': TokenType.dimension,
  'borderRadius': TokenType.dimension,
  'borderWidth': TokenType.dimension,
  'fontSizes': TokenType.dimension,
  'letterSpacing': TokenType.dimension,
  'opacity': TokenType.number,
  'lineHeights': TokenType.number,
  'fontWeights': TokenType.fontWeight,
  'fontFamilies': TokenType.fontFamily,
};

const Map<String, int> _fontWeightNames = {
  'thin': 100,
  'hairline': 100,
  'extra-light': 200,
  'ultra-light': 200,
  'light': 300,
  'normal': 400,
  'regular': 400,
  'book': 400,
  'medium': 500,
  'semi-bold': 600,
  'demi-bold': 600,
  'bold': 700,
  'extra-bold': 800,
  'ultra-bold': 800,
  'black': 900,
  'heavy': 900,
};

class _RawToken {
  _RawToken({
    required this.set,
    required this.path,
    required this.type,
    required this.value,
    required this.description,
  });

  final String set;
  final List<String> path;
  final String? type;
  final Object? value;
  final String? description;

  String get id => path.join('.');
}

/// A token after alias resolution and value parsing.
class _Token {
  _Token({
    required this.raw,
    required this.type,
    required this.value,
    required this.aliasOf,
  });

  final _RawToken raw;
  final TokenType type;

  /// Parsed value: `int` ARGB for colours, `double` for dimensions and
  /// numbers, `int` for weights and milliseconds, `List<String>` for families.
  final Object value;

  /// The token this one aliases directly, if it is an alias.
  final _Token? aliasOf;

  String get id => raw.id;
  List<String> get path => raw.path;
  String? get description => raw.description;
}

final RegExp _aliasPattern = RegExp(r'^\{([^{}]+)\}$');

void _flatten(
  Object? node,
  List<String> path,
  String? inheritedType,
  String set,
  List<_RawToken> out,
  Map<String, String> groupDescriptions,
  List<String> problems,
) {
  final where = path.isEmpty ? 'set "$set"' : '"${path.join('.')}" in "$set"';
  if (node is! Map) {
    problems.add('$where is neither a token nor a group.');
    return;
  }
  final type = node[r'$type'] is String
      ? node[r'$type'] as String
      : inheritedType;
  final description = node[r'$description'] is String
      ? node[r'$description'] as String
      : null;

  if (node.containsKey(r'$value')) {
    out.add(
      _RawToken(
        set: set,
        path: path,
        type: type,
        value: node[r'$value'],
        description: description,
      ),
    );
    return;
  }
  if (description != null && path.isNotEmpty) {
    groupDescriptions[path.join('.')] = description;
  }
  for (final MapEntry(:key, :value) in node.entries) {
    final name = '$key';
    if (name.startsWith(r'$')) continue;
    if (name.isEmpty || name.contains(RegExp(r'[.{}]'))) {
      problems.add(
        '$where has a child named "$name": names cannot be empty '
        'or contain ".", "{" or "}".',
      );
      continue;
    }
    _flatten(
      value,
      [...path, name],
      type,
      set,
      out,
      groupDescriptions,
      problems,
    );
  }
}

/// Resolves and parses every token in one scope (the shared sets, or the
/// shared sets plus one theme's own set).
class _Scope {
  _Scope(this.raw, this.problems, [Map<String, _Token?> resolved = const {}])
    : _resolved = {...resolved};

  final Map<String, _RawToken> raw;
  final List<String> problems;
  final Map<String, _Token?> _resolved;
  final Set<String> _resolving = {};

  _Token? resolve(String id) {
    if (_resolved.containsKey(id)) return _resolved[id];
    final token = raw[id]!;
    if (!_resolving.add(id)) {
      problems.add('"$id" in "${token.set}" is part of an alias cycle.');
      return _resolved[id] = null;
    }
    final result = _resolveUncached(token);
    _resolving.remove(id);
    return _resolved[id] = result;
  }

  _Token? _resolveUncached(_RawToken token) {
    final where = '"${token.id}" in "${token.set}"';
    final declared = token.type == null ? null : _typeNames[token.type];
    if (token.type != null && declared == null) {
      problems.add('$where has an unknown \$type "${token.type}".');
      return null;
    }

    final value = token.value;
    final alias = value is String ? _aliasPattern.firstMatch(value) : null;
    if (alias != null) {
      final targetId = alias.group(1)!;
      if (!raw.containsKey(targetId)) {
        problems.add('$where aliases "{$targetId}", which does not resolve.');
        return null;
      }
      final target = resolve(targetId);
      if (target == null) return null;
      if (declared != null && declared != target.type) {
        problems.add(
          '$where is a ${declared.name} but aliases "{$targetId}", '
          'a ${target.type.name}.',
        );
        return null;
      }
      return _Token(
        raw: token,
        type: target.type,
        value: target.value,
        aliasOf: target,
      );
    }

    if (declared == null) {
      problems.add('$where has no \$type.');
      return null;
    }
    final parsed = _parse(declared, value);
    if (parsed == null) {
      problems.add(
        '$where has a value ${jsonEncode(value)} that is not a valid '
        '${declared.name}.',
      );
      return null;
    }
    return _Token(raw: token, type: declared, value: parsed, aliasOf: null);
  }
}

Object? _parse(TokenType type, Object? value) {
  switch (type) {
    case TokenType.color:
      final hex = value is Map ? value['hex'] : value;
      if (hex is! String) return null;
      final match = RegExp(
        r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$',
      ).firstMatch(hex);
      if (match == null) return null;
      final rgb = int.parse(match.group(1)!, radix: 16);
      var alpha = match.group(2) == null
          ? 0xFF
          : int.parse(match.group(2)!, radix: 16);
      if (value is Map && value['alpha'] is num) {
        alpha = ((value['alpha'] as num) * 255).round();
      }
      return (alpha << 24) | rgb;
    case TokenType.dimension:
      if (value is num) return value.toDouble();
      if (value is Map) {
        final unit = value['unit'];
        final amount = value['value'];
        return unit == 'px' && amount is num ? amount.toDouble() : null;
      }
      if (value is String) {
        final match = RegExp(r'^(-?\d+(?:\.\d+)?)(px)?$').firstMatch(value);
        return match == null ? null : double.parse(match.group(1)!);
      }
      return null;
    case TokenType.number:
      if (value is num) return value.toDouble();
      return value is String ? double.tryParse(value) : null;
    case TokenType.fontWeight:
      final weight = value is String
          ? (_fontWeightNames[value] ?? int.tryParse(value))
          : value;
      if (weight is! int) return null;
      return weight >= 100 && weight <= 900 && weight % 100 == 0
          ? weight
          : null;
    case TokenType.fontFamily:
      if (value is String && value.isNotEmpty) return [value];
      if (value is List &&
          value.isNotEmpty &&
          value.every((name) => name is String && name.isNotEmpty)) {
        return value.cast<String>();
      }
      return null;
    case TokenType.duration:
      num? amount;
      String? unit;
      if (value is Map) {
        amount = value['value'] is num ? value['value'] as num : null;
        unit = value['unit'] is String ? value['unit'] as String : null;
      } else if (value is String) {
        final match = RegExp(r'^(\d+(?:\.\d+)?)(ms|s)$').firstMatch(value);
        if (match != null) {
          amount = num.parse(match.group(1)!);
          unit = match.group(2);
        }
      }
      if (amount == null) return null;
      final ms = switch (unit) {
        'ms' => amount,
        's' => amount * 1000,
        _ => null,
      };
      if (ms == null || ms != ms.roundToDouble()) return null;
      return ms.round();
  }
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/// The two generated files, as text.
class TokenOutputs {
  const TokenOutputs({required this.dart, required this.systemJson});

  final String dart;
  final String systemJson;
}

/// One theme after resolution: its own tokens, in source order.
class _Theme {
  _Theme(this.config, this.set, this.tokens);

  final ThemeConfig config;
  final String set;
  final Map<String, _Token> tokens;

  String get className => 'DesignTokens${_pascal(config.name)}';
}

/// Validates [source] and renders both outputs. Throws a
/// [TokenValidationError] listing every problem when the sets are not valid.
TokenOutputs generate(TokenSource source) {
  final problems = <String>[];

  // --- Set configuration ---------------------------------------------------
  for (final name in source.setOrder) {
    if (!source.sets.containsKey(name)) {
      problems.add('The set order lists "$name", which has no file.');
    }
  }
  for (final name in source.sets.keys) {
    if (!source.setOrder.contains(name)) {
      problems.add('The set "$name" is missing from the set order.');
    }
  }
  if (source.themes.isEmpty) {
    problems.add('No themes are configured.');
  }
  final sharedSets = <String>[
    for (final name in source.setOrder)
      if (source.themes.isNotEmpty &&
          source.themes.every((t) => t.selectedTokenSets[name] == 'source'))
        name,
  ];
  if (source.themes.isNotEmpty && sharedSets.isEmpty) {
    problems.add('No set is a source set for every theme.');
  }
  final themeSets = <ThemeConfig, String>{};
  final themeNames = <String>{};
  for (final theme in source.themes) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9 -]*$').hasMatch(theme.name) ||
        !themeNames.add(_pascal(theme.name))) {
      problems.add('Theme "${theme.name}" needs a unique alphanumeric name.');
    }
    for (final MapEntry(key: set, value: status)
        in theme.selectedTokenSets.entries) {
      if (status == 'source' && !sharedSets.contains(set)) {
        problems.add(
          'Theme "${theme.name}" uses "$set" as a source set, but not every '
          'theme does.',
        );
      }
      if (!source.sets.containsKey(set)) {
        problems.add(
          'Theme "${theme.name}" selects "$set", which has no file.',
        );
      }
    }
    final enabled = [
      for (final MapEntry(key: set, value: status)
          in theme.selectedTokenSets.entries)
        if (status == 'enabled') set,
    ];
    if (enabled.length != 1) {
      problems.add(
        'Theme "${theme.name}" must enable exactly one set of its own; it '
        'enables ${enabled.length}.',
      );
    } else {
      themeSets[theme] = enabled.single;
    }
  }
  if (problems.isNotEmpty) throw TokenValidationError(problems);

  // --- Flatten ------------------------------------------------------------
  final groupDescriptions = <String, String>{};
  List<_RawToken> flattenSet(String set) {
    final out = <_RawToken>[];
    _flatten(
      source.sets[set],
      const [],
      null,
      set,
      out,
      groupDescriptions,
      problems,
    );
    return out;
  }

  final sharedRaw = <String, _RawToken>{};
  for (final set in sharedSets) {
    for (final token in flattenSet(set)) {
      final existing = sharedRaw[token.id];
      if (existing != null) {
        problems.add(
          '"${token.id}" is defined in both "${existing.set}" and '
          '"${token.set}".',
        );
        continue;
      }
      sharedRaw[token.id] = token;
    }
  }
  final themeRaw = <ThemeConfig, Map<String, _RawToken>>{};
  for (final MapEntry(key: theme, value: set) in themeSets.entries) {
    final tokens = <String, _RawToken>{};
    for (final token in flattenSet(set)) {
      if (sharedRaw.containsKey(token.id)) {
        problems.add(
          '"${token.id}" in "$set" redefines a token of '
          '"${sharedRaw[token.id]!.set}".',
        );
        continue;
      }
      if (tokens.containsKey(token.id)) {
        problems.add('"${token.id}" is defined twice in "$set".');
        continue;
      }
      tokens[token.id] = token;
    }
    themeRaw[theme] = tokens;
  }

  // --- Every theme defines every semantic role ----------------------------
  final allRoles = <String>{
    for (final tokens in themeRaw.values) ...tokens.keys,
  };
  for (final MapEntry(key: theme, value: tokens) in themeRaw.entries) {
    for (final role in allRoles) {
      if (!tokens.containsKey(role)) {
        final definedBy = [
          for (final MapEntry(key: other, value: otherTokens)
              in themeRaw.entries)
            if (otherTokens.containsKey(role)) other.name,
        ];
        problems.add(
          'Theme "${theme.name}" does not define "$role" '
          '(defined by ${definedBy.join(', ')}).',
        );
      }
    }
  }

  // --- Resolve --------------------------------------------------------------
  final sharedScope = _Scope(sharedRaw, problems);
  final sharedResults = <String, _Token?>{
    for (final id in sharedRaw.keys) id: sharedScope.resolve(id),
  };
  final shared = <String, _Token>{
    for (final MapEntry(:key, :value) in sharedResults.entries) key: ?value,
  };
  final themes = <_Theme>[];
  for (final MapEntry(key: config, value: tokens) in themeRaw.entries) {
    final scope = _Scope({...sharedRaw, ...tokens}, problems, sharedResults);
    final resolved = <String, _Token>{};
    for (final id in tokens.keys) {
      final token = scope.resolve(id);
      if (token != null) resolved[id] = token;
    }
    themes.add(_Theme(config, themeSets[config]!, resolved));
  }

  // A role has to mean the same kind of value in every theme.
  if (themes.length > 1) {
    for (final role in themes.first.tokens.keys) {
      final types = {
        for (final theme in themes)
          if (theme.tokens[role] != null) theme.tokens[role]!.type,
      };
      if (types.length > 1) {
        problems.add(
          '"$role" has different types across themes: '
          '${types.map((t) => t.name).join(', ')}.',
        );
      }
    }
  }

  // --- Dart names -----------------------------------------------------------
  void checkNames(Iterable<_Token> tokens, String className) {
    final seen = <String, String>{};
    for (final token in tokens) {
      final names = [
        _dartName(token.path),
        if (token.type == TokenType.fontFamily)
          '${_dartName(token.path)}Fallback',
      ];
      for (final name in names) {
        final previous = seen[name];
        if (previous != null) {
          problems.add(
            '"${token.id}" and "$previous" both become $className.$name.',
          );
        }
        seen[name] = token.id;
      }
    }
  }

  checkNames(shared.values, 'DesignTokens');
  for (final theme in themes) {
    checkNames(theme.tokens.values, theme.className);
  }

  if (problems.isNotEmpty) throw TokenValidationError(problems);

  final systemJson = _renderSystemJson(
    shared,
    themes,
    groupDescriptions,
    problems,
  );
  if (problems.isNotEmpty) throw TokenValidationError(problems);

  return TokenOutputs(
    dart: _renderDart(shared, sharedSets, themes),
    systemJson: systemJson,
  );
}

// ---------------------------------------------------------------------------
// Dart output
// ---------------------------------------------------------------------------

String _pascal(String text) => text
    .split(RegExp(r'[^A-Za-z0-9]+'))
    .where((word) => word.isNotEmpty)
    .map((word) => word[0].toUpperCase() + word.substring(1))
    .join();

String _dartName(List<String> path) {
  final words = path.expand((segment) => segment.split('-')).toList();
  final pascal = _pascal(words.join(' '));
  return pascal[0].toLowerCase() + pascal.substring(1);
}

String _dartType(TokenType type) => switch (type) {
  TokenType.color => 'Color',
  TokenType.dimension || TokenType.number => 'double',
  TokenType.fontWeight => 'FontWeight',
  TokenType.fontFamily => 'String',
  TokenType.duration => 'Duration',
};

String _dartDouble(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

String _dartString(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

String _renderDart(
  Map<String, _Token> shared,
  List<String> sharedSets,
  List<_Theme> themes,
) {
  final out = StringBuffer()
    ..writeln(
      '// GENERATED — edit design/tokens/, then run '
      '`dart run tool/design_tokens/generate.dart`.',
    )
    ..writeln('//')
    ..writeln(
      '// Never edit this file by hand: the test suite regenerates it '
      'from the token',
    )
    ..writeln('// sets and fails on any difference.')
    ..writeln();

  final all = [...shared.values, for (final t in themes) ...t.tokens.values];
  final shown = [
    if (all.any((t) => t.type == TokenType.color)) 'Color',
    if (all.any((t) => t.type == TokenType.fontWeight)) 'FontWeight',
  ];
  if (shown.isNotEmpty) {
    out
      ..writeln("import 'dart:ui' show ${shown.join(', ')};")
      ..writeln();
  }

  String reference(_Token target, String fromClass, String suffix) {
    final inShared = shared.containsKey(target.id);
    final name = '${_dartName(target.path)}$suffix';
    if (inShared) {
      return fromClass == 'DesignTokens' ? name : 'DesignTokens.$name';
    }
    return name;
  }

  void writeClass(String className, String doc, Iterable<_Token> tokens) {
    out
      ..writeln(_docComment(doc, indent: ''))
      ..writeln('abstract final class $className {');
    String? group;
    var first = true;
    for (final token in tokens) {
      final tokenGroup = token.path.length > 1
          ? token.path.sublist(0, token.path.length - 1).join('.')
          : token.path.first;
      // One blank line between members, and a section comment per group: the
      // formatter keeps both, so the output is already in its final form.
      if (!first) out.writeln();
      if (tokenGroup != group) {
        out.writeln('  // $tokenGroup');
        group = tokenGroup;
      }
      first = false;
      final description = token.description;
      if (description != null && description.isNotEmpty) {
        out.writeln(_docComment(description, indent: '  '));
      }
      final name = _dartName(token.path);
      final alias = token.aliasOf;
      if (token.type == TokenType.fontFamily) {
        final families = token.value as List<String>;
        out.writeln(
          _declaration(
            'String',
            name,
            alias != null
                ? reference(alias, className, '')
                : _dartString(families.first),
          ),
        );
        if (alias != null) {
          out.writeln(
            _declaration(
              'List<String>',
              '${name}Fallback',
              reference(alias, className, 'Fallback'),
            ),
          );
        } else if (families.length > 1) {
          out.writeln(
            _listDeclaration(
              '${name}Fallback',
              families.skip(1).map(_dartString).toList(),
            ),
          );
        } else {
          out.writeln(
            _declaration('List<String>', '${name}Fallback', '<String>[]'),
          );
        }
        continue;
      }
      final expression = alias != null
          ? reference(alias, className, '')
          : switch (token.type) {
              TokenType.color =>
                'Color(0x${(token.value as int).toRadixString(16).padLeft(8, '0').toUpperCase()})',
              TokenType.dimension ||
              TokenType.number => _dartDouble(token.value as double),
              TokenType.fontWeight => 'FontWeight.w${token.value}',
              TokenType.duration => 'Duration(milliseconds: ${token.value})',
              TokenType.fontFamily => throw StateError('handled above'),
            };
      out.writeln(_declaration(_dartType(token.type), name, expression));
    }
    out.writeln('}');
  }

  writeClass(
    'DesignTokens',
    'The design tokens every theme shares, from '
        '${sharedSets.map((s) => '`$tokensDirPath/$s.json`').join(', ')}.',
    shared.values,
  );
  for (final theme in themes) {
    out.writeln();
    writeClass(
      theme.className,
      'The ${theme.config.name} theme\'s semantic tokens, from '
      '`$tokensDirPath/${theme.set}.json`.',
      theme.tokens.values,
    );
  }
  return out.toString();
}

/// One `static const` line, split the way the formatter splits it when it
/// does not fit in 80 columns.
String _declaration(String type, String name, String expression) {
  final head = '  static const $type $name = ';
  final single = '$head$expression;';
  if (single.length <= 80) return single;
  final call = RegExp(r'^([A-Za-z_][\w.]*)\((.*)\)$').firstMatch(expression);
  if (call != null && '$head${call.group(1)}('.length <= 80) {
    return '$head${call.group(1)}(\n    ${call.group(2)},\n  );';
  }
  final split = '  static const $type $name =';
  if (split.length <= 80 && '      $expression;'.length <= 80) {
    return '$split\n      $expression;';
  }
  throw StateError('Token name too long to format: $name');
}

String _listDeclaration(String name, List<String> items) {
  final head = '  static const List<String> $name = <String>[';
  final single = '$head${items.join(', ')}];';
  if (single.length <= 80) return single;
  return [head, for (final item in items) '    $item,', '  ];'].join('\n');
}

String _docComment(String text, {required String indent}) {
  final prefix = '$indent/// ';
  final width = 80 - prefix.length;
  final lines = <String>[];
  var line = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if (line.isEmpty) {
      line = word;
    } else if (line.length + 1 + word.length <= width) {
      line = '$line $word';
    } else {
      lines.add(line);
      line = word;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines.map((l) => '$prefix$l').join('\n');
}

// ---------------------------------------------------------------------------
// Design-system listing
// ---------------------------------------------------------------------------

/// Fonts the design-system reference loads: asset facts, not tokens.
const List<Map<String, String>> _fontFiles = [
  {
    'family': 'Inter',
    'file': 'fonts/Inter.ttf',
    'weight': '100 900',
    'style': 'normal',
  },
  {
    'family': 'CupolaServices',
    'file': 'fonts/CupolaServices.otf',
    'weight': '400',
    'style': 'normal',
  },
];

/// Colours the listing composes from a scheme colour and a theme opacity,
/// because the app composes them the same way.
const Map<String, (String, String)> _derivedColors = {
  'glass-surface': ('color.surface-container', 'opacity.glass-surface'),
};

/// Second-level colour groups whose name the listing drops, so
/// `color.service.radarr` is listed as `radarr`.
const Set<String> _flatColorGroups = {'base', 'brand', 'service', 'status'};

String _css(int argb, [double? alphaOverride]) {
  final alpha = alphaOverride ?? ((argb >> 24) & 0xFF) / 255;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  if (alpha == 1) {
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
  return 'rgba($r, $g, $b, ${alpha.toStringAsFixed(2)})';
}

String _px(double value) =>
    '${value == value.roundToDouble() ? value.round() : value}px';

String _cssFamily(List<String> families) =>
    families.map((f) => f.contains(' ') ? '"$f"' : f).join(', ');

/// Inter's tracking curve in logical pixels, the one the app applies to every
/// role whose tracking is not authored — the light theme's, rounded for a
/// listing.
double _interTracking(double size) {
  final px = (-0.0223 + 0.185 * math.exp(-0.1745 * size)) * size;
  final rounded = (px * 100).round() / 100;
  return rounded == 0 ? 0 : rounded;
}

String _renderSystemJson(
  Map<String, _Token> shared,
  List<_Theme> themes,
  Map<String, String> groupDescriptions,
  List<String> problems,
) {
  // --- Colours ---------------------------------------------------------------
  String coreColorName(List<String> path) {
    final rest = path.sublist(1);
    if (rest.length > 1 && _flatColorGroups.contains(rest.first)) {
      return rest.sublist(1).join('-');
    }
    return rest.join('-');
  }

  final colorEntries = <Map<String, Object?>>[];
  final listedName = <_Token, String>{};

  final roleIds = [
    for (final MapEntry(key: id, value: token) in themes.first.tokens.entries)
      if (token.path.first == 'color' && token.type == TokenType.color) id,
  ];
  final roleNames = {
    for (final id in roleIds) id.substring(6).replaceAll('.', '-'),
  };

  final coreColors = [
    for (final token in shared.values)
      if (token.path.first == 'color' &&
          token.type == TokenType.color &&
          !roleNames.contains(coreColorName(token.path)))
        token,
  ];
  for (final token in coreColors) {
    listedName[token] = coreColorName(token.path);
  }
  for (final id in roleIds) {
    for (final theme in themes) {
      listedName[theme.tokens[id]!] = id.substring(6).replaceAll('.', '-');
    }
  }

  /// `{name}` when every theme aliases the same listed token under another
  /// name; otherwise null.
  String? sharedAlias(List<_Token> perTheme, String ownName) {
    final targets = perTheme.map((t) => t.aliasOf?.id).toSet();
    if (targets.length != 1 || targets.single == null) return null;
    final target = perTheme.first.aliasOf!;
    final name = listedName[target];
    if (name == null || name == ownName) return null;
    return '{$name}';
  }

  for (final id in roleIds) {
    final perTheme = [for (final theme in themes) theme.tokens[id]!];
    final name = listedName[perTheme.first]!;
    colorEntries.add({
      'name': name,
      'value':
          sharedAlias(perTheme, name) ??
          {
            for (final theme in themes)
              theme.config.id: _css(theme.tokens[id]!.value as int),
          },
      'usage': ?(perTheme.first.description),
    });
  }
  for (final MapEntry(key: name, value: (colorId, opacityId))
      in _derivedColors.entries) {
    // A source that does not carry the opacity simply has no such colour.
    if (themes.every((theme) => theme.tokens[opacityId] == null)) continue;
    final missing = [
      for (final theme in themes)
        if (theme.tokens[colorId] == null || theme.tokens[opacityId] == null)
          theme.config.name,
    ];
    if (missing.isNotEmpty) {
      problems.add(
        '"$name" needs "$colorId" and "$opacityId" in: ${missing.join(', ')}.',
      );
      continue;
    }
    colorEntries.add({
      'name': name,
      'value': {
        for (final theme in themes)
          theme.config.id: _css(
            theme.tokens[colorId]!.value as int,
            theme.tokens[opacityId]!.value as double,
          ),
      },
      'usage': ?(themes.first.tokens[opacityId]!.description),
    });
  }
  for (final token in coreColors) {
    final name = listedName[token]!;
    final alias = token.aliasOf;
    final aliasName = alias == null ? null : listedName[alias];
    colorEntries.add({
      'name': name,
      'value': aliasName != null && aliasName != name
          ? '{$aliasName}'
          : _css(token.value as int),
      'usage': ?(token.description),
    });
  }

  // --- Type -----------------------------------------------------------------
  final families = <String, String>{
    for (final token in shared.values)
      if (token.path.length == 3 &&
          token.path[0] == 'type' &&
          token.path[1] == 'family' &&
          token.type == TokenType.fontFamily)
        token.path[2]: _cssFamily(token.value as List<String>),
    'services': 'CupolaServices',
  };

  final roleGroups = <String, Map<String, Map<String, _Token>>>{};
  for (final token in shared.values) {
    if (token.path.length != 4 || token.path[0] != 'type') continue;
    roleGroups
            .putIfAbsent(token.path[1], () => {})
            .putIfAbsent(token.path[2], () => {})[token.path[3]] =
        token;
  }
  final typeGroups = <Map<String, Object?>>[];
  for (final MapEntry(key: groupName, value: roles) in roleGroups.entries) {
    final styles = <Map<String, Object?>>[];
    for (final MapEntry(key: role, value: props) in roles.entries) {
      final roleId = 'type.$groupName.$role';
      final size = props['font-size'];
      final weight = props['font-weight'];
      final height = props['line-height'];
      if (size == null || weight == null || height == null) {
        problems.add('"$roleId" needs font-size, font-weight and line-height.');
        continue;
      }
      final fontSize = size.value as double;
      final letterSpacing = props['letter-spacing'] == null
          ? _interTracking(fontSize)
          : (props['letter-spacing']!.value as double);
      styles.add({
        'name': const {'large', 'medium', 'small'}.contains(role)
            ? '$groupName-$role'
            : role,
        'fontSize': _px(fontSize),
        'lineHeight': height.value,
        'fontWeight': weight.value,
        'letterSpacing': '${letterSpacing}px',
        'usage': ?(groupDescriptions[roleId] ?? size.description),
      });
    }
    typeGroups.add({
      'name': _pascal(groupName),
      'family': 'sans',
      'styles': styles,
    });
  }

  // --- Lists ------------------------------------------------------------------
  List<Map<String, Object?>> dimensionList(String group, String prefix) => [
    for (final token in shared.values)
      if (token.path.length == 2 &&
          token.path.first == group &&
          token.type == TokenType.dimension)
        {
          'name': '$prefix-${token.path[1]}',
          'value': _px(token.value as double),
          'usage': ?(token.description),
        },
  ];

  // --- Shadows ----------------------------------------------------------------
  final shadowLayers = <String, Map<String, Map<String, _Token>>>{};
  for (final token in shared.values) {
    if (token.path.length != 4 || token.path.first != 'shadow') continue;
    shadowLayers
            .putIfAbsent(token.path[1], () => {})
            .putIfAbsent(token.path[2], () => {})[token.path[3]] =
        token;
  }
  String cssLength(double value) => value == 0 ? '0' : _px(value);
  final shadowTokens = <Map<String, Object?>>[];
  for (final MapEntry(key: level, value: layers) in shadowLayers.entries) {
    final value = <String, String>{};
    for (final theme in themes) {
      final parts = <String>[];
      for (final MapEntry(key: layer, value: props) in layers.entries) {
        final alpha = theme.tokens['elevation.$level.$layer'];
        final ink = props['color'] ?? theme.tokens['color.shadow'];
        final x = props['offset-x'];
        final y = props['offset-y'];
        final blur = props['blur'];
        if (alpha == null ||
            ink == null ||
            x == null ||
            y == null ||
            blur == null) {
          problems.add(
            'Shadow "$level.$layer" needs offset-x, offset-y, blur, a colour '
            'and "elevation.$level.$layer" in theme "${theme.config.name}".',
          );
          continue;
        }
        final spread = props['spread']?.value as double? ?? 0;
        parts.add(
          [
            cssLength(x.value as double),
            cssLength(y.value as double),
            cssLength(blur.value as double),
            if (spread != 0) cssLength(spread),
            _css(ink.value as int, alpha.value as double),
          ].join(' '),
        );
      }
      value[theme.config.id] = parts.join(', ');
    }
    shadowTokens.add({
      'name': level,
      'value': value,
      'usage': ?(groupDescriptions['shadow.$level']),
    });
  }

  final listing = <String, Object?>{
    'name': 'Cupola',
    'version': 1,
    'color': {
      'themes': [
        for (final theme in themes)
          {'id': theme.config.id, 'name': theme.config.name},
      ],
      'tokens': colorEntries,
    },
    'type': {'fonts': _fontFiles, 'families': families, 'groups': typeGroups},
    'spacing': {'tokens': dimensionList('space', 'space')},
    'radius': {'tokens': dimensionList('radius', 'radius')},
    'shadow': {'note': ?groupDescriptions['shadow'], 'tokens': shadowTokens},
    'breakpoint': {
      'note': ?groupDescriptions['breakpoint'],
      'tokens': dimensionList('breakpoint', 'bp'),
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(listing)}\n';
}
