import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_flow.dart';

const _shown =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _other =
    '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0';

void main() {
  group('a certificate trusted on an invite\'s word', () {
    test('is the one the invite vouched for, where nothing was trusted', () {
      expect(
        trustedOnInvite(
          trusted: null,
          invited: _shown,
          shown: _shown,
          fromSealedPackage: true,
        ),
        isTrue,
      );
    });

    test('never on the word of a link anyone can compose', () {
      expect(
        trustedOnInvite(
          trusted: null,
          invited: _shown,
          shown: _shown,
          fromSealedPackage: false,
        ),
        isFalse,
      );
    });

    test('is never another one', () {
      expect(
        trustedOnInvite(
          trusted: null,
          invited: _other,
          shown: _shown,
          fromSealedPackage: true,
        ),
        isFalse,
      );
      expect(
        trustedOnInvite(
          trusted: null,
          invited: null,
          shown: _shown,
          fromSealedPackage: true,
        ),
        isFalse,
      );
    });

    test('never replaces one this device already trusted', () {
      expect(
        trustedOnInvite(
          trusted: _other,
          invited: _shown,
          shown: _shown,
          fromSealedPackage: true,
        ),
        isFalse,
      );
    });
  });
}
