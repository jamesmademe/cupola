/// A read the flow is no longer waiting for does not write what the screens draw.
///
/// The notifier outlives its screens and a scan of a big folder takes minutes,
/// so the answer for the folder the person left can arrive after the one for the
/// folder they chose.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/import/data/manual_import_service.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';

/// A service whose answers the test hands over one at a time, in the order it
/// likes.
class _HeldService extends ManualImportService {
  _HeldService() : super(client: FakeApiClient(), service: ServiceKey.radarr);

  final scans = <String, List<Completer<List<ManualImportItem>>>>{};
  final listings = <String, List<Completer<ManualImportFileSystemResult>>>{};

  Completer<List<ManualImportItem>> scan(String folder, int nth) =>
      scans[folder]![nth];

  @override
  Future<List<ManualImportRootFolder>> getRootFolders() async => const [
    ManualImportRootFolder(id: 1, path: '/downloads'),
  ];

  @override
  Future<ManualImportFileSystemResult> getFileSystem(String path) {
    final held = Completer<ManualImportFileSystemResult>();
    (listings[path] ??= []).add(held);
    return held.future;
  }

  @override
  Future<List<ManualImportItem>> getManualImportItems({
    required String folder,
    bool filterExistingFiles = true,
  }) {
    final held = Completer<List<ManualImportItem>>();
    (scans[folder] ??= []).add(held);
    return held.future;
  }
}

ManualImportItem _movie(String path) => ManualImportItem.fromJson({
  'path': path,
  'name': path.split('/').last,
  'movie': {'id': path.hashCode.abs() + 1, 'title': 'Movie $path'},
});

ManualImportFileSystemResult _listing(String parent) =>
    ManualImportFileSystemResult(parent: parent);

void main() {
  late _HeldService service;
  late ProviderContainer container;
  late ManualImportFlowNotifier notifier;

  ManualImportFlowState state() => container.read(manualImportFlowProvider);

  setUp(() {
    service = _HeldService();
    container = ProviderContainer(
      overrides: [
        manualImportServiceProvider(
          ServiceKey.radarr,
        ).overrideWith((ref) => service),
      ],
    );
    addTearDown(container.dispose);
    notifier = container.read(manualImportFlowProvider.notifier);
  });

  /// Opens the flow on `/A`, listing already answered.
  Future<void> openOnA() async {
    final started = notifier.start(ServiceKey.radarr, force: true);
    await pumpEventQueue();
    service.listings['/']!.single.complete(_listing('/'));
    await started;
    final chosen = notifier.selectFolder('/A');
    await pumpEventQueue();
    service.listings['/A']!.single.complete(_listing('/'));
    await chosen;
  }

  test(
    'a scan that answers after another folder was chosen is dropped',
    () async {
      await openOnA();

      // The scan of A is slow. The person goes back and picks B, and scans it.
      final scanA = notifier.loadSelectedFolderItems();
      await pumpEventQueue();
      expect(state().isLoadingItems, isTrue);

      final chosen = notifier.selectFolder('/B');
      await pumpEventQueue();
      expect(
        state().isLoadingItems,
        isFalse,
        reason: 'the scan of A is no longer being waited for',
      );
      service.listings['/B']!.single.complete(_listing('/'));
      await chosen;

      final scanB = notifier.loadSelectedFolderItems();
      await pumpEventQueue();
      service.scan('/B', 0).complete([_movie('/B/b.mkv')]);
      await scanB;

      // A answers last.
      service.scan('/A', 0).complete([_movie('/A/a.mkv')]);
      await scanA;

      expect(state().selectedFolder, '/B');
      expect(state().items.map((item) => item.path), ['/B/b.mkv']);
      expect(state().selectedPaths, {'/B/b.mkv'});
      expect(state().isLoadingItems, isFalse);
    },
  );

  test(
    'of two scans of the same folder, the later one is the one drawn',
    () async {
      await openOnA();

      final first = notifier.loadSelectedFolderItems();
      await pumpEventQueue();
      final second = notifier.loadSelectedFolderItems();
      await pumpEventQueue();

      service.scan('/A', 1).complete([_movie('/A/new.mkv')]);
      await second;
      service.scan('/A', 0).complete([_movie('/A/old.mkv')]);
      await first;

      expect(state().items.map((item) => item.path), ['/A/new.mkv']);
      expect(state().isLoadingItems, isFalse);
    },
  );

  test(
    'a folder listing that answers late does not replace the newer one',
    () async {
      await openOnA();

      final toB = notifier.selectFolder('/B');
      await pumpEventQueue();
      final toC = notifier.selectFolder('/C');
      await pumpEventQueue();

      service.listings['/C']!.single.complete(_listing('C parent'));
      await toC;
      service.listings['/B']!.single.complete(_listing('B parent'));
      await toB;

      expect(state().selectedFolder, '/C');
      expect(state().fileSystem?.parent, 'C parent');
      expect(state().isLoadingBrowse, isFalse);
    },
  );

  test('a scan does not end the listing of the folder it reads', () async {
    await openOnA();
    final toB = notifier.selectFolder('/B');
    await pumpEventQueue();

    // Review scans while the listing of B is still on its way.
    final scan = notifier.loadSelectedFolderItems();
    await pumpEventQueue();
    service.listings['/B']!.single.complete(_listing('B parent'));
    await toB;
    service.scan('/B', 0).complete([_movie('/B/b.mkv')]);
    await scan;

    expect(state().fileSystem?.parent, 'B parent');
    expect(state().isLoadingBrowse, isFalse);
    expect(state().items.map((item) => item.path), ['/B/b.mkv']);
  });
}
