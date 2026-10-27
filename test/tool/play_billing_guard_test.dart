import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android ships without Play Billing: **no package in `pubspec.lock` brings
/// `in_app_purchase_android`.**
///
/// The tip jar is App Store only (`DonationService.usesIAP`); Android opens
/// Ko-fi. The `in_app_purchase` umbrella still pulled the Android plugin, and
/// with it `com.android.billingclient` and the BILLING permission, into every
/// APK and AAB. Play reviews that library's version on each upload, and
/// F-Droid refuses it outright, for a flow Android never runs. Cupola depends
/// on the StoreKit half alone. Re-adding the umbrella, or any package that
/// depends on the Android plugin, brings the library back without a single
/// visible change, so the lockfile is the thing to check.
void main() {
  test('pubspec.lock resolves no Android in-app purchase plugin', () {
    final lock = File('pubspec.lock').readAsStringSync();
    for (final name in ['in_app_purchase', 'in_app_purchase_android']) {
      expect(
        RegExp('^  $name:\$', multiLine: true).hasMatch(lock),
        isFalse,
        reason:
            '$name is in pubspec.lock. It puts Play Billing into the Android '
            'build; depend on in_app_purchase_storekit instead.',
      );
    }
  });
}
