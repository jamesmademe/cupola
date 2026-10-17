import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/domain/unraid_alerts.dart';

UnraidArray _array(List<UnraidDisk> disks) =>
    UnraidArray(state: 'STARTED', usedFraction: null, disks: disks);

UnraidNotifications _notifications(List<UnraidNotification> items) =>
    UnraidNotifications.fromJson({
      'list': [
        for (final n in items)
          {
            'id': n.id,
            'title': n.title,
            'subject': n.subject,
            'description': n.description,
            'importance': n.importance,
            'type': 'UNREAD',
          },
      ],
    });

UnraidNotification _notice(
  String id,
  String importance,
  String subject, {
  String description = '',
}) => UnraidNotification(
  id: id,
  title: 'Unraid Status',
  subject: subject,
  description: description,
  importance: importance,
  type: 'UNREAD',
);

void main() {
  test('a slot the array flagged says what happened to it', () {
    String said(String name, String status) => unraidFlaggedSlotHeadline(
      UnraidDisk(name: name, status: status, temp: 34),
    );
    expect(said('disk2', 'DISK_DSBL'), 'Disk 2 is disabled');
    expect(said('parity', 'DISK_NP_MISSING'), 'Parity is missing');
    expect(said('parity2', 'DISK_NP_DSBL'), 'Parity 2 is missing and disabled');
    expect(
      said('disk3', 'DISK_WRONG'),
      'Disk 3 is not the disk the array expects',
    );
    expect(said('cache', 'DISK_SOMETHING'), 'Unraid flags Cache');
  });

  test('flagged slots, then unread notifications at warning or alert, '
      'without saying a flagged slot twice', () {
    final alerts = unraidAlerts(
      array: _array(const [
        UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 38),
        UnraidDisk(name: 'disk2', status: 'DISK_DSBL', temp: 36),
        UnraidDisk(name: 'parity2', status: 'DISK_NP', temp: null),
      ]),
      notifications: _notifications([
        _notice(
          'a',
          'ALERT',
          'Alert [TOWER] - Disk 2 in error state (disk dsbl)',
        ),
        _notice(
          'b',
          'WARNING',
          'Warning [TOWER] - Disk 12 SMART health [197]',
          description: 'WDC_WD80EFZZ (sdk)',
        ),
        _notice('c', 'NORMAL', 'Notice [TOWER] - Parity check finished'),
        _notice('d', 'INFO', 'Docker update available'),
      ]),
    );
    expect(alerts.map((a) => a.title), [
      'Disk 2 is disabled',
      'Disk 12 SMART health [197]',
    ]);
    expect(alerts.first.isDisk, isTrue);
    expect(alerts.first.reason, 'DISK_DSBL');
    expect(alerts.last.isDisk, isFalse);
    expect(alerts.last.reason, 'WDC_WD80EFZZ (sdk)');
  });

  test('a SMART warning names its disk from the title', () {
    expect(
      unraidNotificationHeadline(
        const UnraidNotification(
          id: 's',
          title: 'Unraid Disk 1 SMART health [187]',
          subject: 'Warning [TOWER] - reported uncorrect is 1',
          description: 'WDC_WD40EFRX (sdb)',
          importance: 'WARNING',
          type: 'UNREAD',
        ),
      ),
      'Disk 1: reported uncorrect is 1',
    );
  });

  test('nothing flagged and nothing unread is nothing', () {
    expect(
      unraidAlerts(
        array: _array(const [
          UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 52),
        ]),
        notifications: null,
      ),
      isEmpty,
      reason: 'a warm disk is Unraid\'s own notification to raise',
    );
  });
}
