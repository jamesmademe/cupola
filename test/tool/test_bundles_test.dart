import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_bundles/test_bundles.dart';

/// The real tree, as the runner reads it.
Map<String, String> _sources() => {
  for (final file in Directory(testDirPath).listSync(recursive: true))
    if (file is File &&
        file.path.endsWith('_test.dart') &&
        !file.path.split('/').any((part) => part.startsWith('zz_')))
      file.path.substring('$testDirPath/'.length): file.readAsStringSync(),
};

void main() {
  group('the plan of the real suite', () {
    final sources = _sources();
    final skipped = skippedTagsIn(File('dart_test.yaml').readAsStringSync());
    final plan = planTests(sources, skippedTags: skipped);

    test('every test file runs exactly once, or is left out', () {
      // A file in two bundles runs twice; a file in none never runs, and
      // the gate is green over a test nobody ran.
      final placed = [
        for (final paths in plan.bundles.values) ...paths,
        ...plan.standalone,
        ...plan.leftOut,
      ];
      expect(placed.toSet().length, placed.length);
      expect(placed.toSet(), sources.keys.toSet());
    });

    test('only the tiers dart_test.yaml skips by default are left out', () {
      expect(skipped, {'e2e', 'catalog'});
      for (final path in plan.leftOut) {
        expect(
          libraryAnnotations(sources[path]!)['Tags'],
          everyElement(isIn(skipped)),
          reason: path,
        );
      }
    });

    test('a file declaring anything for its library keeps its own file', () {
      // A bundle imports a file and calls its main: the annotations of the
      // file's library would silently stop applying.
      for (final paths in plan.bundles.values) {
        for (final path in paths) {
          expect(libraryAnnotations(sources[path]!), isEmpty, reason: path);
        }
      }
    });
  });

  group('libraryAnnotations', () {
    test('reads the header, with the tags it carries', () {
      const source = '''
@Tags(['e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

@visibleForTesting
void main() {}
''';
      expect(libraryAnnotations(source), {
        'Tags': ['e2e'],
        'Timeout': <String>[],
      });
    });

    test('an annotation past the first directive is not the library\'s', () {
      const source = '''
import 'package:flutter_test/flutter_test.dart';

@Tags(['e2e'])
void main() {}
''';
      expect(libraryAnnotations(source), isEmpty);
    });
  });

  group('planTests', () {
    test('a file skipped by its tags is left out, whatever else it says', () {
      final plan = planTests(
        {
          'e2e/a_test.dart': "@Tags(['e2e'])\n@Timeout.none\nlibrary;\n",
          'e2e/b_test.dart': "@Tags(['e2e', 'slow'])\nlibrary;\n",
          'core/c_test.dart': "import 'x.dart';\n",
        },
        skippedTags: {'e2e'},
      );

      expect(plan.leftOut, ['e2e/a_test.dart']);
      // `slow` is not skipped by default: the file runs, from its own file.
      expect(plan.standalone, ['e2e/b_test.dart']);
      expect(plan.bundles, {
        'core': ['core/c_test.dart'],
      });
    });

    test('files are bundled by their first two folders', () {
      expect(
        bundleNameOf('features/truenas/data/x_test.dart'),
        'features_truenas',
      );
      expect(bundleNameOf('features/truenas/x_test.dart'), 'features_truenas');
      expect(bundleNameOf('core/x_test.dart'), 'core');
      expect(bundleNameOf('x_test.dart'), 'root');
    });
  });

  test('a bundle runs each file inside a group named after its path', () {
    final source = bundleSource([
      'features/truenas/a_test.dart',
      'features/truenas/data/b_test.dart',
    ]);

    // From `.dart_tool/test_bundles/`, two levels under the package root.
    expect(
      source,
      contains("import '../../test/features/truenas/a_test.dart' as t0;"),
    );
    expect(
      source,
      contains("import '../../test/features/truenas/data/b_test.dart' as t1;"),
    );
    expect(
      source,
      contains("  group('features/truenas/a_test.dart', t0.main);"),
    );
    expect(
      source,
      contains("  group('features/truenas/data/b_test.dart', t1.main);"),
    );
  });

  group('shardOf', () {
    final weights = {for (var i = 0; i < 23; i++) 'file$i': (i * 37) % 11 + 1};

    test('the shards split the targets, each in exactly one', () {
      final shards = [for (var i = 1; i <= 4; i++) shardOf(weights, i, 4)];
      final all = [for (final shard in shards) ...shard];

      expect(all.toSet().length, all.length);
      expect(all.toSet(), weights.keys.toSet());
    });

    test('the same targets always make the same shards', () {
      // Every CI job plans on its own: they must agree on who runs what.
      expect(shardOf(weights, 2, 3), shardOf(Map.of(weights), 2, 3));
    });

    test('no shard carries much more than its share', () {
      final loads = [
        for (var i = 1; i <= 3; i++)
          shardOf(weights, i, 3).fold(0, (sum, t) => sum + weights[t]!),
      ];
      final heaviest = weights.values.reduce((a, b) => a > b ? a : b);
      expect(
        loads.reduce((a, b) => a > b ? a : b) -
            loads.reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(heaviest),
      );
    });

    test('one shard is everything', () {
      expect(shardOf(weights, 1, 1).toSet(), weights.keys.toSet());
    });
  });
}
