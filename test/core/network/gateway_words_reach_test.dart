/// The surfaces that used to turn only a reason into words now name the
/// gateway that answered: the fallback (`Something in front of Radarr
/// answered instead of it`) is left for a gateway nothing could identify.
/// `gateway_words_guard_test.dart` holds the calls to it; this holds a few
/// of them to the words themselves.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/import/domain/manual_import_errors.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _access = AccessGatewayAnswer(
  kind: AccessGatewayKind.cloudflareAccess,
  credentialsSent: false,
  gatewayHost: 'cupola-home.cloudflareaccess.com',
  serviceHost: 'radarr.example.com',
);

DioException _behindAccess() => DioException(
  requestOptions: RequestOptions(path: '/api/v3/movie'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/v3/movie'),
    statusCode: 401,
  ),
  error: _access,
);

void main() {
  test('a region whose sources all failed names the gateway', () {
    final coverage = SourceCoverage.merge([
      SourceCoverage.failure(ServiceKey.radarr, _behindAccess()),
    ]);

    expect(
      coverageFailureSentence(coverage),
      'Cloudflare Access answered instead of Radarr.',
    );
  });

  test('a total that leaves the source out groups it under its own word', () {
    final coverage = SourceCoverage.merge([
      SourceCoverage.answeredBy(ServiceKey.sonarr),
      SourceCoverage.failure(ServiceKey.radarr, _behindAccess()),
    ]);

    expect(coverage.gateways.values.single, same(_access));
    expect(coverageNote(coverage), 'Not in the total: Radarr');
  });

  test('a search lane says what answered in its place', () {
    final lane = GlobalSearchServiceResults.fault((
      instance: const ServiceInstance(
        id: 'radarr',
        service: ServiceKey.radarr,
        url: 'https://radarr.example.com',
        credential: 'k',
      ),
      name: '',
    ), _behindAccess());

    expect(lane.stateWord, 'Behind Cloudflare Access');
    expect(
      lane.faultSentence,
      'No Radarr results, Behind Cloudflare Access. Retry is per lane.',
    );
  });

  test('a manual import that met a gateway names it and its remedy', () {
    expect(
      mapImportError(_behindAccess(), ServiceKey.radarr),
      'Cloudflare Access answered instead of Radarr. Add a service token in '
      'Settings.',
    );
  });
}
