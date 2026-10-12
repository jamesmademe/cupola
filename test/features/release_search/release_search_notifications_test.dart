import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/release_search/data/release_search_notifications.dart';

/// Records what [ReleaseSearchNotifications] hands the plugin; answers
/// everything else with nothing.
class _RecordingPlugin implements FlutterLocalNotificationsPlugin {
  InitializationSettings? settings;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    this.settings = settings;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _res = 'android/app/src/main/res';

void main() {
  // The small icon was `@mipmap/ic_launcher`: a full-colour icon Android masks
  // into a white blob, and a resource this app has not had since its icons were
  // regenerated, so the plugin refused to initialise and nothing ever posted.
  group('the Android small icon', () {
    test('is the one handed to the plugin, and it exists', () async {
      final plugin = _RecordingPlugin();
      await ReleaseSearchNotifications(plugin).initialise();

      final icon = plugin.settings?.android?.defaultIcon;
      expect(icon, ReleaseSearchNotifications.androidSmallIcon);
      expect(
        File('$_res/drawable/$icon.xml').existsSync(),
        isTrue,
        reason: 'the plugin looks the icon up as a drawable by this name',
      );
    });

    test('is a white alpha mask on the 24dp status-bar grid', () {
      final xml = File(
        '$_res/drawable/${ReleaseSearchNotifications.androidSmallIcon}.xml',
      ).readAsStringSync();

      expect(xml, contains('<vector'));
      expect(xml, contains('android:width="24dp"'));
      expect(xml, contains('android:height="24dp"'));
      // Android keeps only the alpha channel of a small icon: any colour is
      // thrown away, and a translucent or gradient fill turns into a smudge.
      final colours = RegExp(
        r'android:(?:fillColor|strokeColor)="([^"]+)"',
      ).allMatches(xml).map((m) => m.group(1)!.toUpperCase()).toSet();
      expect(colours, {'#FFFFFFFF'});
      expect(xml, isNot(contains('gradient')));
      expect(xml, isNot(contains('fillAlpha')));
    });

    test('survives release resource shrinking', () {
      // Named only from Dart, so the shrinker cannot see it is used.
      final keep = File('$_res/raw/keep.xml').readAsStringSync();
      expect(
        keep,
        contains('@drawable/${ReleaseSearchNotifications.androidSmallIcon}'),
      );
    });
  });
}
