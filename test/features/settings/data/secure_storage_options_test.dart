import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/settings_service.dart';

void main() {
  test('a Keystore error is reported, never answered by wiping the store', () {
    final options = secureStorageAndroidOptions.toMap();

    expect(options['resetOnError'], 'false');
    expect(options['migrateWithBackup'], 'true');
  });
}
