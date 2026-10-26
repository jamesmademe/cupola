import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';

import '../../../test_helpers/fake_services.dart';

SeerrRequest _row(int id, {String? title}) => SeerrRequest(
  id: id,
  status: RequestStatus.pendingApproval,
  type: 'movie',
  createdAt: '2026-08-01T10:00:00.000Z',
  media: RequestMedia(id: id, tmdbId: id, mediaType: 'movie', title: title),
);

/// Answers the rows it is given, counts its pages read and its titles read,
/// and names a row it hydrates.
class _CountingSeerr extends FakeSeerrService {
  int pagesRead = 0;
  int hydrations = 0;

  @override
  Future<List<SeerrRequest>> getRequestRows() async {
    pagesRead++;
    return SeerrRequestList([_row(pagesRead)], total: 7);
  }

  @override
  Future<List<SeerrRequest>> hydrate(List<SeerrRequest> requests) async {
    hydrations++;
    final named = [
      for (final request in requests)
        request.copyWith(
          media: request.media?.copyWith(title: 'Title ${request.id}'),
        ),
    ];
    return switch (requests) {
      SeerrRequestList(:final total, :final isPartial) => SeerrRequestList(
        named,
        total: total,
        isPartial: isPartial,
      ),
      _ => named,
    };
  }
}

void main() {
  late _CountingSeerr seerr;
  late ProviderContainer container;

  setUp(() {
    seerr = _CountingSeerr();
    container = ProviderContainer(
      overrides: [seerrServiceProvider.overrideWith((ref) => seerr)],
    );
    addTearDown(container.dispose);
  });

  test('the rows are read without a title read', () async {
    final rows = await container.read(requestRowsProvider.future);

    expect(rows.single.media?.title, isNull);
    expect(seerr.pagesRead, 1);
    expect(seerr.hydrations, 0);
  });

  test(
    'the list with titles is the rows, hydrated, and no second walk',
    () async {
      final rows = await container.read(requestRowsProvider.future);
      final titled = await container.read(requestsProvider.future);

      expect(rows.single.media?.title, isNull);
      expect(titled.single.media?.title, 'Title 1');
      expect(seerr.pagesRead, 1);
      // What the rows said of their size, the titled list says.
      expect((titled as SeerrRequestList).total, 7);
    },
  );

  test('invalidateSeerrRequests reads the pages again for both', () async {
    await container.read(requestsProvider.future);

    invalidateSeerrRequests(container);
    final rows = await container.read(requestRowsProvider.future);
    final titled = await container.read(requestsProvider.future);

    expect(seerr.pagesRead, 2);
    expect(rows.single.id, 2);
    expect(titled.single.media?.title, 'Title 2');
  });

  test('dropping the list with titles alone reads no page: the trap', () async {
    await container.read(requestsProvider.future);

    container.invalidate(requestsProvider);
    final titled = await container.read(requestsProvider.future);

    // The rows are as old as before, which is why the guard forbids it.
    expect(seerr.pagesRead, 1);
    expect(titled.single.id, 1);
  });
}
