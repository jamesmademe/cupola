import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['CUPOLA_TESTLAB_SCREENSHOT_DIR'] ??
        '.ai/scratch/zz_testlab/screenshots',
  )..createSync(recursive: true);

  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          await File(
            '${directory.path}/$name.png',
          ).writeAsBytes(bytes, flush: true);
          return true;
        },
    writeResponseOnFailure: true,
  );
}
