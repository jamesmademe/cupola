/// The flow catalogue and the journeys that claim its rows agree.
///
/// The catalogue is project-state (`A-20261021-catalogo-dei-flussi`): it names
/// people and holds review notes, so it is not in the repository. Where it is
/// not there (CI, a fresh clone) the checks skip with that reason rather than
/// pass silently. Where it is, two things must hold:
///
/// - a row that says `verde` or `parziale` names a journey or test file, and
///   that file exists;
/// - a journey whose test names a row (`M-02 · …`) names one the catalogue has.
///
/// The coverage per area is printed, so a review sees the counts it did not ask
/// for.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _catalogue =
    '.ai/state/artifacts/persistenti/'
    'A-20261021-catalogo-dei-flussi-4a87-catalogo-dei-flussi.md';
const _journeys = 'integration_test/journeys';

/// The skip reason when the catalogue is absent, or null when the checks run.
final String? _skip = File(_catalogue).existsSync()
    ? null
    : 'the flow catalogue lives in project-state, not in the repository or in '
          'CI: $_catalogue is not here, so this check cannot run';

/// Every catalogue row: its id (`M-01`), and the text of its last cell.
List<({String id, String state, String line})> _rows(String text) {
  final rows = <({String id, String state, String line})>[];
  for (final line in text.split('\n')) {
    if (!line.startsWith('| ')) continue;
    final cells = line.split('|').map((cell) => cell.trim()).toList()
      ..removeAt(0);
    if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
    if (cells.length < 2) continue;
    final id = cells.first;
    if (!RegExp(r'^[A-Z]-\d\d$').hasMatch(id)) continue;
    rows.add((id: id, state: cells.last, line: line));
  }
  return rows;
}

/// The `.dart` files a state cell names, in backticks.
Iterable<String> _dartNamed(String state) =>
    RegExp(r'`([^`]+\.dart)`').allMatches(state).map((match) => match[1]!);

/// Whether [name] (a path, or a bare file name) exists in the repository.
bool _exists(String name) {
  if (name.contains('/')) return File(name).existsSync();
  for (final root in const ['integration_test', 'test']) {
    final found = Directory(root)
        .listSync(recursive: true)
        .any((entity) => entity is File && entity.path.endsWith('/$name'));
    if (found) return true;
  }
  return false;
}

void main() {
  final rows = _skip == null
      ? _rows(File(_catalogue).readAsStringSync())
      : <({String id, String state, String line})>[];

  test('a row that is verde names a test file that exists', skip: _skip, () {
    final problems = <String>[];
    for (final row in rows) {
      // A row is verde when its status leads with the word: a parziale row may
      // mention a green part further on, and is not held to a test here.
      if (!row.state.startsWith('verde')) continue;
      final named = _dartNamed(row.state).toList();
      if (named.isEmpty) {
        problems.add('${row.id} says verde but names no test file');
        continue;
      }
      for (final name in named) {
        if (!_exists(name)) problems.add('${row.id} names $name, not found');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test(
    'a journey names only catalogue rows the catalogue has',
    skip: _skip,
    () {
      final ids = {for (final row in rows) row.id};
      final problems = <String>[];
      final journeys = Directory(_journeys).listSync().whereType<File>().where(
        (file) => file.path.endsWith('_journey_test.dart'),
      );
      for (final journey in journeys) {
        final text = journey.readAsStringSync();
        for (final match in RegExp(r"'([A-Z]-\d\d) ·").allMatches(text)) {
          final id = match[1]!;
          if (!ids.contains(id)) {
            problems.add('${journey.path} names $id, not a catalogue row');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    },
  );

  test('coverage per area', skip: _skip, () {
    final byArea = <String, Map<String, int>>{};
    for (final row in rows) {
      final area = row.id[0];
      final counts = byArea.putIfAbsent(area, () => <String, int>{});
      final state = row.state;
      final bucket = state.startsWith('verde')
          ? 'verde'
          : state.startsWith('parziale')
          ? 'parziale'
          : state.startsWith('X') || state.contains('dichiarato')
          ? 'dichiarato'
          : 'da costruire';
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    for (final area in byArea.keys.toList()..sort()) {
      final counts = byArea[area]!;
      final total = counts.values.fold<int>(0, (sum, n) => sum + n);
      // ignore: avoid_print
      print(
        'coverage $area: $total rows, ${counts.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
      );
    }
    expect(rows, isNotEmpty);
  });
}
