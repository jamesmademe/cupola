import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

void main() {
  group('ServiceKey setup guidance', () {
    // The defect this guards: the onboarding walk carried its own copy of the
    // note list and TrueNAS was not in it, so the minimum supported version was
    // stated in Settings and nowhere in the flow that asks for the address.
    test('every service with a settings note also has a walk note', () {
      final missing = ServiceKey.values
          .where((k) => k.setupNote != null && k.walkNote == null)
          .map((k) => k.name)
          .toList();
      expect(missing, isEmpty);
    });

    test('TrueNAS states its minimum version in both voices', () {
      expect(ServiceKey.truenas.setupNote, contains(kTrueNasMinVersion));
      expect(ServiceKey.truenas.walkNote, contains(kTrueNasMinVersion));
    });
  });
}
