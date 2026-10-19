/// The Fix sheet opens on the connection's whole library, and every sheet used
/// to download it again: thirty files fixed by hand were thirty `GET /movie`.
/// The flow reads it once, shares it while in flight, forgets a failure, and
/// drops it when a new flow starts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/import/data/manual_import_service.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';

class _CountingService extends ManualImportService {
  _CountingService()
    : super(client: FakeApiClient(), service: ServiceKey.radarr);

  int reads = 0;
  bool fail = false;

  @override
  Future<List<ManualImportLookupResult>> getLibraryMatches() async {
    reads++;
    await Future<void>.delayed(Duration.zero);
    if (fail) throw StateError('library did not answer');
    return const [ManualImportLookupResult(id: 1, title: 'Arrival', raw: {})];
  }
}

void main() {
  late _CountingService service;
  late ProviderContainer container;

  setUp(() {
    service = _CountingService();
    container = ProviderContainer(
      overrides: [
        manualImportServiceProvider(
          ServiceKey.radarr,
        ).overrideWith((ref) => service),
      ],
    );
    addTearDown(container.dispose);
    container.read(manualImportFlowProvider.notifier).state =
        const ManualImportFlowState(service: ServiceKey.radarr);
  });

  ManualImportFlowNotifier notifier() =>
      container.read(manualImportFlowProvider.notifier);

  test('two sheets, one of them opened while the first read is in flight, '
      'ask the server once', () async {
    final first = notifier().getLibraryMatches();
    final second = notifier().getLibraryMatches();
    expect(await first, hasLength(1));
    expect(await second, hasLength(1));
    await notifier().getLibraryMatches();

    expect(service.reads, 1);
  });

  test('a read that failed is not kept: the next sheet asks again', () async {
    service.fail = true;
    await expectLater(notifier().getLibraryMatches(), throwsStateError);

    service.fail = false;
    expect(await notifier().getLibraryMatches(), hasLength(1));
    expect(service.reads, 2);
  });

  test('a new flow reads the library again', () async {
    await notifier().getLibraryMatches();
    await notifier().start(ServiceKey.radarr, force: true);
    await notifier().getLibraryMatches();

    expect(service.reads, 2);
  });
}
