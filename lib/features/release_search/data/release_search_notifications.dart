import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:cupola/features/release_search/domain/release_search_job.dart';

/// What a finished search should say, if anything.
///
/// A pure function so the whole decision — including the rule that a finished
/// search never interrupts — is testable without a platform channel.
@immutable
class ReleaseSearchNotice {
  const ReleaseSearchNotice({required this.title, required this.body});

  final String title;
  final String body;
}

/// Composes the notice for a finished job, or null when none should be shown.
///
/// Three rules live here:
///
/// * **Nothing while the app is in the foreground.** The user is mid-task; the
///   badge lights and the detail page updates instead. A search completing must
///   never take the screen away from what they are doing.
/// * **A nil result still notifies.** Zero releases is the answer they were
///   waiting for, and withholding it makes the feature feel broken.
/// * **A failure names the target in the title.** A notification that does not
///   say *which* search stopped is useless.
ReleaseSearchNotice? noticeFor(
  ReleaseSearchJob job, {
  required bool appInForeground,
  required bool notificationsEnabled,
}) {
  if (!notificationsEnabled) return null;
  if (appInForeground) return null;
  if (job.isActive) return null;

  final label = job.target.label;

  return switch (job.status) {
    ReleaseSearchJobStatus.completed =>
      job.releaseCount == 0
          ? ReleaseSearchNotice(
              title: 'No releases found for $label',
              body: 'Your indexers answered — nothing matched.',
            )
          : ReleaseSearchNotice(
              title:
                  '${job.releaseCount} release'
                  '${job.releaseCount == 1 ? '' : 's'} for $label',
              body:
                  'Grabbable for ${kGrabWindow.inMinutes} minutes. '
                  'Tap to pick one.',
            ),
    ReleaseSearchJobStatus.failed =>
      job.failure?.kind == ReleaseSearchFailureKind.cancelled
          // Nobody needs telling about something they did on purpose.
          ? null
          : ReleaseSearchNotice(
              title: 'Search stopped — $label',
              body: job.failure?.headline ?? 'It did not finish.',
            ),
    _ => null,
  };
}

/// Posts the notices, and asks for permission only when the user opts in.
///
/// Permission is never requested at launch: it is requested the first time the
/// user switches "Notify me when one finishes" on, which is the only moment the
/// request means anything to them.
class ReleaseSearchNotifications {
  ReleaseSearchNotifications([
    FlutterLocalNotificationsPlugin? plugin,
    this.onTap,
  ]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Told a tapped notification's payload — the job id. Owned by the provider
  /// that can navigate; the notice's "Tap to pick one" is a lie without it.
  final void Function(String? payload)? onTap;

  bool _initialised = false;

  /// Whether this platform can show these notifications at all.
  ///
  /// Windows and Linux have no branch in [requestPermission] and no
  /// initialization settings in [initialise], so the toggle can never turn on
  /// there — and the settings screen words that as a platform gap rather than
  /// sending the user to hunt through system settings that are not the cause.
  static bool get platformSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// One channel, default importance. Not high: a search the user asked for
  /// finishing is news, not an alarm.
  static const _androidChannelId = 'release_searches';
  static const _androidChannelName = 'Release searches';
  static const _androidChannelDescription =
      'Tells you when a background release search has finished.';

  /// Deliberately no `zonedSchedule` anywhere in this class — that single
  /// omission is what keeps the Android manifest at one permission and clear of
  /// the Play-restricted exact-alarm permissions.
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;
    // Best-effort on purpose: a platform without the plugin behind it (or a
    // test) must not take down whatever asked. The same posture show() takes —
    // a notification that cannot post is a notification lost, nothing more.
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Not requested here: asking at launch, before the user has expressed
          // any interest, is the pattern this deliberately avoids.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) =>
            onTap?.call(response.payload),
      );
      // A notification tapped after the OS relaunched the app still deserves
      // its landing. Asked once, here, because this is the only moment early
      // enough to catch it and late enough for a router to exist behind
      // [onTap] — provided something calls initialise at startup, which the
      // release-search lifecycle widget does.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        onTap?.call(launch?.notificationResponse?.payload);
      }
    } catch (_) {
      // Nothing to clean up; requestPermission still answers false and the
      // toggle stays honest.
    }
  }

  /// Asks the OS, at the moment the user turns the toggle on.
  Future<bool> requestPermission() async {
    await initialise();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final darwin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (darwin != null) {
      return await darwin.requestPermissions(alert: true, sound: true) ?? false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (mac != null) {
      return await mac.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  /// What the OS currently allows, as opposed to what the user asked for.
  ///
  /// The two drift apart on their own: a permission granted here can be revoked
  /// in system settings later, and nothing tells the app. Without this the
  /// toggle keeps claiming to be on while every notice is silently dropped —
  /// which is the failure mode a user reads as "the feature is broken".
  ///
  /// Null means *unknown*, and it is a real answer rather than a failure: the
  /// platform has no branch here (Windows, Linux), or the plugin is not behind
  /// it (a test). An unknown state must never be rendered as "denied", because
  /// that would send someone to fix a permission nothing ever asked for.
  Future<bool?> permissionGranted() async {
    await initialise();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) return await android.areNotificationsEnabled();

      final darwin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (darwin != null) {
        return (await darwin.checkPermissions())?.isEnabled;
      }

      final mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      if (mac != null) {
        return (await mac.checkPermissions())?.isEnabled;
      }
    } catch (_) {
      // Unknown, not denied — see above.
    }
    return null;
  }

  Future<void> show(ReleaseSearchNotice notice, {required String jobId}) async {
    await initialise();
    // Fire-and-forget by contract: the caller never awaits this, so an error
    // here would surface as an unhandled zone error with nobody to act on it.
    try {
      await _plugin.show(
        id: jobId.hashCode,
        title: notice.title,
        body: notice.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        payload: jobId,
      );
    } catch (_) {
      // A notification that cannot post is a notification lost, nothing more.
    }
  }
}
