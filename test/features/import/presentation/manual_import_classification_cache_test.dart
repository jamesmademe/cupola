import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

ManualImportItem _file(String name) => ManualImportItem.fromJson({
  'id': name.hashCode,
  'path': '/downloads/$name.mkv',
  'name': name,
  'size': 700000000,
  'movie': {'id': 7, 'title': name},
  'quality': {
    'quality': {'id': 5, 'name': 'WEBDL-720p'},
  },
});

/// The five lists the classification serves, in one record so a test can say
/// "the same lists" in one line.
typedef _Split = (
  List<ManualImportItem>,
  List<ManualImportItem>,
  List<ManualImportItem>,
  List<ManualImportItem>,
  List<ManualImportItem>,
);

_Split _split(ManualImportFlowState state) => (
  state.readyItems,
  state.attentionItems,
  state.otherItems,
  state.importedItems,
  state.inFlightItems,
);

void _expectSame(_Split a, _Split b, {required bool same, String? reason}) {
  final pairs = [
    (a.$1, b.$1, 'ready'),
    (a.$2, b.$2, 'attention'),
    (a.$3, b.$3, 'other'),
    (a.$4, b.$4, 'imported'),
    (a.$5, b.$5, 'inFlight'),
  ];
  for (final (left, right, name) in pairs) {
    // `inFlight` is a shared const empty list while no batch is blocked, so it
    // is only checked for being kept, never for being rebuilt.
    if (!same && name == 'inFlight') continue;
    expect(identical(left, right), same, reason: '$name: ${reason ?? ''}');
  }
}

void main() {
  // The classified lists are cached per (items list, service, blocked paths).
  // Anything else a state carries must not be able to reach the classification
  // without one of those three changing. Inputs and their effect:
  //
  //   items           : the key; a new list reclassifies.
  //   service         : the key; a new service reclassifies.
  //   blockedPaths    : the key (command and submittedPaths); a command that
  //                     fails or a submitted batch reclassifies.
  //   selectedPaths   : read by selectedItems only, not by the five lists.
  //   fixSelectionPaths, selectedFolder, currentPath, qualityOptions,
  //   importMode, isLoading*, error, rootFolders: not read by the five lists.
  //
  // Text filter and facet chips are inputs of the screen's view memo, not of
  // this classification.
  group('the classification of a scan', () {
    late List<ManualImportItem> items;
    late ManualImportFlowState base;

    setUp(() {
      items = [_file('a'), _file('b'), _file('c')];
      base = ManualImportFlowState(service: ServiceKey.radarr, items: items);
    });

    test('a selection change keeps the lists (a tick does not reclassify)', () {
      final before = _split(base);
      final ticked = base.copyWith(selectedPaths: {items.first.path});

      _expectSame(before, _split(ticked), same: true, reason: 'tick');
    });

    test('the other inputs that are not in the key keep the lists', () {
      final before = _split(base);

      _expectSame(
        before,
        _split(base.copyWith(fixSelectionPaths: {items[1].path})),
        same: true,
        reason: 'fix selection',
      );
      _expectSame(
        before,
        _split(base.copyWith(isLoadingItems: true)),
        same: true,
        reason: 'loading flag',
      );
      _expectSame(
        before,
        _split(base.copyWith(importMode: ManualImportMode.copy)),
        same: true,
        reason: 'import mode',
      );
      // Submitted paths alone do not block anything without a command.
      _expectSame(
        before,
        _split(base.copyWith(submittedPaths: {items.first.path})),
        same: true,
        reason: 'submitted paths without a command',
      );
    });

    test('a new items list reclassifies', () {
      final before = _split(base);
      final next = base.copyWith(items: [...items]);

      _expectSame(before, _split(next), same: false, reason: 'items');
    });

    test('a new service reclassifies', () {
      final before = _split(base);
      final next = base.copyWith(service: ServiceKey.sonarr);

      _expectSame(before, _split(next), same: false, reason: 'service');
    });

    test('a blocked batch reclassifies', () {
      final before = _split(base);
      final failed = ManualImportCommandStatus.fromJson({
        'id': 77,
        'status': 'failed',
      });
      final running = ManualImportCommandStatus.fromJson({
        'id': 78,
        'status': 'started',
      });
      final spent = base.copyWith(
        submittedItems: [items.first],
        submittedPaths: {items.first.path},
        command: running,
      );

      _expectSame(
        before,
        _split(spent),
        same: false,
        reason: 'batch in flight',
      );
      // A failed command releases the batch again: the blocked set changes
      // back to empty, so the lists are rebuilt.
      final released = spent.copyWith(command: failed);
      _expectSame(
        _split(spent),
        _split(released),
        same: false,
        reason: 'batch released by a failed command',
      );
    });
  });
}
