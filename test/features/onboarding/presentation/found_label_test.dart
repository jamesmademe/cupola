import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/onboarding/presentation/widgets/onboarding_found.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('foundLabel', () {
    test("a second Radarr is called by what follows the service's name", () {
      expect(foundLabel(ServiceKey.radarr, 'Radarr 4K'), '4K');
      expect(foundLabel(ServiceKey.radarr, 'radarr 4k'), '4k');
    });

    test("a name that is only the service's own adds nothing", () {
      expect(foundLabel(ServiceKey.sonarr, 'Sonarr'), '');
      expect(foundLabel(ServiceKey.sonarr, ' sonarr '), '');
    });

    test('any other name is kept whole', () {
      expect(foundLabel(ServiceKey.radarr, 'Movies UHD'), 'Movies UHD');
      expect(foundLabel(ServiceKey.radarr, 'Radarrish'), 'Radarrish');
    });
  });
}
