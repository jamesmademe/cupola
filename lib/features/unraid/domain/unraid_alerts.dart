/// What on an Unraid server needs somebody, for Needs you: the slots the
/// array has flagged, and the notifications Unraid raised at warning or alert
/// that nobody has read.
library;

import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

/// One thing on the server that needs somebody, already in the app's words.
typedef UnraidAlert = ({
  /// Unique on its server: a slot's name, or a notification's id.
  String id,

  /// The headline: `Disk 2 is disabled`.
  String title,

  /// Unraid's own words, for Why?, when the headline is the app's.
  String? reason,

  /// When it was raised, when Unraid said.
  DateTime? occurredAt,

  /// A flagged slot (true), whose place is the array, or a notification.
  bool isDisk,
});

/// What [array] and [notifications] say needs somebody: every slot the array
/// flagged ([UnraidDisk.flagged]) first, then each unread notification at
/// warning or alert.
///
/// A notification about a slot already listed is left out: Unraid announces
/// a disabled disk once (`Disk 2 in error state (disk dsbl)`) and the slot
/// stays disabled after it is read, so the slot is the lasting fact and the
/// notification would say it twice. A warm disk is not here: Unraid raises
/// its own notification at its own thresholds, which is.
List<UnraidAlert> unraidAlerts({
  required UnraidArray? array,
  required UnraidNotifications? notifications,
}) {
  final flagged = [
    for (final disk in array?.drives ?? const <UnraidDisk>[])
      if (disk.flagged) disk,
  ];
  final named = {for (final disk in flagged) unraidSlotName(disk.name)};
  return [
    for (final disk in flagged)
      (
        id: 'slot-${disk.name}',
        title: unraidFlaggedSlotHeadline(disk),
        reason: disk.status.trim().isEmpty ? null : disk.status.trim(),
        occurredAt: null,
        isDisk: true,
      ),
    for (final notification
        in notifications?.items ?? const <UnraidNotification>[])
      if (_needsSomebody(notification) &&
          !named.any((slot) => _mentions(notification, slot)))
        (
          id: 'notification-${notification.id}',
          title: unraidNotificationHeadline(notification),
          reason: _why(notification),
          occurredAt: notification.timestamp,
          isDisk: false,
        ),
  ];
}

/// How a slot is called aloud: `disk2` is `Disk 2`, `parity2` is `Parity 2`,
/// `cache` is `Cache`, the way Unraid's own pages and notifications name
/// them.
String unraidSlotName(String name) {
  final match = RegExp(r'^([A-Za-z]+?)(\d+)$').firstMatch(name.trim());
  final word = match?.group(1) ?? name.trim();
  final number = match?.group(2);
  final title = word.isEmpty
      ? 'Disk'
      : '${word[0].toUpperCase()}${word.substring(1)}';
  return number == null ? title : '$title $number';
}

/// A flagged slot, said as what happened to it. Unraid's token
/// (`DISK_DSBL`) stays behind Why?.
String unraidFlaggedSlotHeadline(UnraidDisk disk) {
  final slot = unraidSlotName(disk.name);
  return switch (disk.status.trim().toUpperCase()) {
    'DISK_DSBL' => '$slot is disabled',
    'DISK_NP_DSBL' => '$slot is missing and disabled',
    'DISK_NP_MISSING' => '$slot is missing',
    'DISK_DSBL_NEW' => '$slot is disabled, with a new disk to rebuild onto',
    'DISK_INVALID' => '$slot holds data the array cannot trust',
    'DISK_WRONG' => '$slot is not the disk the array expects',
    _ => 'Unraid flags $slot',
  };
}

/// A notification's headline: its subject without Unraid's prefix
/// (`Alert [TOWER] - `), which the card says by its tone and its source,
/// and led by the slot when only the title names it: Unraid's SMART
/// warnings put the disk in the title (`Unraid Disk 1 SMART health [187]`)
/// and the fact in the subject (`reported uncorrect is 1`), which reads
/// `Disk 1: reported uncorrect is 1`. The title when there is no subject.
String unraidNotificationHeadline(UnraidNotification notification) {
  final headline = _headline(notification);
  final slot = _slotIn(notification.title);
  if (slot == null || _slotIn(headline) != null) return headline;
  return '$slot: ${headline[0].toLowerCase()}${headline.substring(1)}';
}

/// The slot [text] names (`Disk 1`, `Parity 2`, `Cache`), as it names it.
String? _slotIn(String text) {
  final found = RegExp(
    r'\b(disk \d+|parity(?: \d+)?|cache\w*)\b',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  return found == null ? null : unraidSlotName(found.replaceAll(' ', ''));
}

String _headline(UnraidNotification notification) {
  final subject = notification.subject
      .replaceFirst(
        RegExp(
          r'^\s*(alert|warning|notice)\s*\[[^\]]*\]\s*-\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  final words = subject.isNotEmpty ? subject : notification.title.trim();
  if (words.isEmpty) return 'Unraid raised an alert';
  final plain = words.endsWith('.')
      ? words.substring(0, words.length - 1)
      : words;
  return '${plain[0].toUpperCase()}${plain.substring(1)}';
}

bool _needsSomebody(UnraidNotification notification) => const {
  'ALERT',
  'WARNING',
}.contains(notification.importance.trim().toUpperCase());

/// Whether [notification] is about [slot] (`Disk 2`, `Parity`), as Unraid
/// writes it in a subject or a description: `Disk 2 in error state`.
bool _mentions(UnraidNotification notification, String slot) {
  final pattern = RegExp(
    '\\b${RegExp.escape(slot)}\\b(?! ?\\d)',
    caseSensitive: false,
  );
  return pattern.hasMatch(notification.subject) ||
      pattern.hasMatch(notification.title);
}

/// What Unraid wrote under the subject (the disk's model and device, the
/// figures of a parity check), when there is any.
String? _why(UnraidNotification notification) {
  final description = notification.description.trim();
  return description.isEmpty ? null : description;
}
