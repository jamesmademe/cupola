import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/search_results_loader.dart';

/// "No results" is said only after the service answered. The loader used to
/// catch every failure into `[]`, so a section search against a Radarr that
/// did not answer drew exactly what an empty answer draws.
void main() {
  test('an empty query asks nothing', () async {
    var asked = false;
    final result = await loadNullableSearchResults<String>(
      query: '',
      lookup: (_) async {
        asked = true;
        return const [];
      },
    );
    expect(result, isNull);
    expect(asked, isFalse);
  });

  test('an empty answer is an empty list', () async {
    final result = await loadNullableSearchResults<String>(
      query: 'dune',
      lookup: (_) async => const [],
    );
    expect(result, isEmpty);
  });

  test('a failure is the failure, never an empty answer', () async {
    await expectLater(
      loadNullableSearchResults<String>(
        query: 'dune',
        lookup: (_) async => throw const SocketException('Connection refused'),
      ),
      throwsA(isA<SocketException>()),
    );
  });
}
