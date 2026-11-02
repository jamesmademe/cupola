/// Runs the test suite as a few dozen bundles instead of one file at a time.
///
/// `flutter test` compiles every test file on its own, one after the other,
/// and with nine hundred files that compilation, not the tests, is where the
/// time goes: raising `--concurrency` changes nothing, because the compiler
/// is the queue. A bundle is one generated file that imports every test file
/// of a folder and calls each `main` inside a group named after it, so the
/// compiler sees a few dozen files instead. Measured on the whole suite:
/// 128 s instead of 454 s, and less than half the CPU.
///
/// ```sh
/// dart run tool/test_bundles/test_bundles.dart                # the default suite
/// dart run tool/test_bundles/test_bundles.dart --shard 2/3    # one CI shard
/// dart run tool/test_bundles/test_bundles.dart -- --coverage  # flags for flutter test
/// dart run tool/test_bundles/test_bundles.dart --write        # write, do not run
/// ```
///
/// The bundles are written under `.dart_tool/test_bundles/`, rewritten on
/// every run: outside `test/`, so a plain `flutter test` never runs them
/// beside the files they import, and in a folder that git, `dart format .`
/// and the analyzer all leave alone. A failure names the test file it came
/// from: its group is the file's path under `test/`. One file is still run
/// on its own with `flutter test <file>`, as always.
///
/// What a bundle changes is that the files of a folder share one isolate. A
/// test that needs what a fresh isolate gives it says so itself (see
/// `test/test_helpers/real_network.dart`), rather than relying on running
/// first. A file with a library-level annotation (`@Tags`, `@TestOn`, ...)
/// keeps its own file, since a bundle would drop the annotation; one whose
/// tags are all skipped by default in `dart_test.yaml` (the e2e tier and the
/// design catalog) is left out, as `flutter test` would only skip it after
/// compiling it.
///
/// Pure Dart on purpose (`dart:io` only), like the design-token generator.
library;

import 'dart:io';

/// The folder every test file lives under, relative to the package root.
const String testDirPath = 'test';

/// Where the bundles are written, two levels under the package root.
const String bundleDirPath = '.dart_tool/test_bundles';

/// What the suite is run as: the bundles, the files that keep their own
/// file, and those left out because they would only be skipped.
class TestPlan {
  const TestPlan({
    required this.bundles,
    required this.standalone,
    required this.leftOut,
  });

  /// Bundle name to the test files it imports, as paths under `test/`.
  final Map<String, List<String>> bundles;

  /// Files run as they are, paths under `test/`.
  final List<String> standalone;

  /// Files not run at all by default, paths under `test/`.
  final List<String> leftOut;
}

/// Plans [sources] (test file path under `test/` to its source) given the
/// tags `dart_test.yaml` skips by default.
TestPlan planTests(
  Map<String, String> sources, {
  Set<String> skippedTags = const {},
}) {
  final bundles = <String, List<String>>{};
  final standalone = <String>[];
  final leftOut = <String>[];
  for (final path in sources.keys.toList()..sort()) {
    final annotations = libraryAnnotations(sources[path]!);
    if (annotations.isNotEmpty) {
      // A file skipped by its tags is skipped whatever else it declares.
      final tags = annotations['Tags'] ?? const [];
      final skipped = tags.isNotEmpty && tags.every(skippedTags.contains);
      (skipped ? leftOut : standalone).add(path);
      continue;
    }
    (bundles[bundleNameOf(path)] ??= []).add(path);
  }
  return TestPlan(bundles: bundles, standalone: standalone, leftOut: leftOut);
}

/// The folder a test file is bundled by: its first two folders under `test/`
/// (`features/truenas`), its only one (`core` for `core/x_test.dart`), or
/// the empty string for a file directly under `test/`.
String bundleFolderOf(String path) {
  final folders = path.split('/')..removeLast();
  return folders.take(2).join('/');
}

/// The bundle a test file belongs to, named after [bundleFolderOf]: `root`
/// for the files directly under `test/`.
String bundleNameOf(String path) {
  final folder = bundleFolderOf(path);
  return folder.isEmpty ? 'root' : folder.replaceAll('/', '_');
}

final _annotation = RegExp(r'^@(\w+)\b(.*)$', multiLine: true);
final _quoted = RegExp('''['"]([^'"]+)['"]''');

/// The library-level annotations of a test file, by name, with the strings
/// each one carries (the tags of `@Tags`). Only the part before the first
/// directive is read: an annotation there belongs to the library.
Map<String, List<String>> libraryAnnotations(String source) {
  final directive = RegExp(
    r'^(library|import|export|part)\b',
    multiLine: true,
  ).firstMatch(source);
  final header = directive == null ? '' : source.substring(0, directive.start);
  return {
    for (final match in _annotation.allMatches(header))
      match.group(1)!: [
        for (final quoted in _quoted.allMatches(match.group(2)!))
          quoted.group(1)!,
      ],
  };
}

/// The tags `dart_test.yaml` skips by default: a `tags:` entry whose body
/// has a `skip:` line. Read by hand to keep this script free of packages.
Set<String> skippedTagsIn(String yaml) {
  final skipped = <String>{};
  String? tag;
  var inTags = false;
  for (final line in yaml.split('\n')) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      inTags = line.startsWith('tags:');
      tag = null;
    } else if (inTags && indent == 2 && line.trimRight().endsWith(':')) {
      tag = line.trim().replaceAll(':', '');
    } else if (inTags && tag != null && line.trim().startsWith('skip:')) {
      skipped.add(tag);
    }
  }
  return skipped;
}

/// The source of the bundle over [paths] (under `test/`, one folder's).
String bundleSource(List<String> paths) {
  final buffer = StringBuffer()
    ..writeln(
      '// Generated by tool/test_bundles/test_bundles.dart. Do not edit.',
    )
    ..writeln('// The test files of test/${bundleFolderOf(paths.first)}.')
    ..writeln()
    ..writeln("import 'package:flutter_test/flutter_test.dart' show group;")
    ..writeln();
  for (final (index, path) in paths.indexed) {
    buffer.writeln("import '../../$testDirPath/$path' as t$index;");
  }
  buffer
    ..writeln()
    ..writeln('void main() {');
  for (final (index, path) in paths.indexed) {
    buffer.writeln("  group('$path', t$index.main);");
  }
  buffer.writeln('}');
  return buffer.toString();
}

/// Splits [weights] (run target to its cost) into [count] shards as even as
/// greedy placement makes them, heaviest first, and returns shard [index]
/// (1-based). The same input always gives the same shards.
List<String> shardOf(Map<String, int> weights, int index, int count) {
  final shards = List.generate(count, (_) => <String>[]);
  final loads = List.filled(count, 0);
  final targets = weights.keys.toList()
    ..sort((a, b) {
      final byWeight = weights[b]!.compareTo(weights[a]!);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  for (final target in targets) {
    var lightest = 0;
    for (var shard = 1; shard < count; shard++) {
      if (loads[shard] < loads[lightest]) lightest = shard;
    }
    shards[lightest].add(target);
    loads[lightest] += weights[target]!;
  }
  return shards[index - 1]..sort();
}

Future<void> main(List<String> args) async {
  final split = args.indexOf('--');
  final own = split < 0 ? args : args.sublist(0, split);
  final forwarded = split < 0 ? const <String>[] : args.sublist(split + 1);

  var writeOnly = false;
  var shardIndex = 1;
  var shardCount = 1;
  for (var i = 0; i < own.length; i++) {
    switch (own[i]) {
      case '--write':
        writeOnly = true;
      case '--shard' when i + 1 < own.length:
        final parts = own[++i].split('/');
        final index = parts.length == 2 ? int.tryParse(parts[0]) : null;
        final count = parts.length == 2 ? int.tryParse(parts[1]) : null;
        if (index == null || count == null || index < 1 || index > count) {
          _usage('--shard takes <index>/<count>, for example 2/3');
        }
        shardIndex = index;
        shardCount = count;
      default:
        _usage('unknown argument ${own[i]}');
    }
  }

  final sources = <String, String>{
    for (final file in Directory(testDirPath).listSync(recursive: true))
      if (file is File && _isTestFile(file.path))
        _underTest(file.path): file.readAsStringSync(),
  };
  final config = File('dart_test.yaml');
  final plan = planTests(
    sources,
    skippedTags: config.existsSync()
        ? skippedTagsIn(config.readAsStringSync())
        : const {},
  );

  final bundleDir = Directory(bundleDirPath);
  if (bundleDir.existsSync()) bundleDir.deleteSync(recursive: true);
  bundleDir.createSync(recursive: true);
  final weights = <String, int>{};
  for (final MapEntry(key: name, value: paths) in plan.bundles.entries) {
    final target = '$bundleDirPath/${name}_test.dart';
    File(target).writeAsStringSync(bundleSource(paths));
    weights[target] = paths.fold(0, (sum, path) => sum + sources[path]!.length);
  }
  // Asked for, the skipped tiers run too, each from its own file.
  final runSkipped = forwarded.contains('--run-skipped');
  for (final path in [...plan.standalone, if (runSkipped) ...plan.leftOut]) {
    weights['$testDirPath/$path'] = sources[path]!.length;
  }

  final targets = shardOf(weights, shardIndex, shardCount);
  stdout.writeln(
    'test_bundles: ${plan.bundles.length} bundles over '
    '${plan.bundles.values.fold(0, (sum, paths) => sum + paths.length)} files, '
    '${plan.standalone.length} on their own, '
    '${plan.leftOut.length} left out (tags skipped by default)'
    '${shardCount > 1 ? '; shard $shardIndex/$shardCount runs ${targets.length}' : ''}.',
  );
  if (writeOnly) return;

  final flutter = await Process.start(
    'flutter',
    ['test', ...forwarded, ...targets],
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  exit(await flutter.exitCode);
}

bool _isTestFile(String path) {
  final normalised = path.replaceAll(r'\', '/');
  final name = normalised.split('/').last;
  return name.endsWith('_test.dart') &&
      !normalised.split('/').any((part) => part.startsWith('zz_'));
}

String _underTest(String path) =>
    path.replaceAll(r'\', '/').substring('$testDirPath/'.length);

Never _usage(String problem) {
  stderr.writeln('test_bundles: $problem');
  stderr.writeln(
    'usage: dart run tool/test_bundles/test_bundles.dart '
    '[--write] [--shard <index>/<count>] [-- <flutter test flags>]',
  );
  exit(64);
}
