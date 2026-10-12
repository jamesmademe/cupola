import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/domain/manual_import_status.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

ManualImportItem _item(Map<String, dynamic> json) =>
    ManualImportItem.fromJson({'path': '/downloads/x.mkv', ...json});

void main() {
  group('manualImportItemStatus', () {
    test('a matched movie resolves to Ready on the success tone', () {
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 42, 'title': 'Some Movie'},
        }),
      );
      expect(info.label, 'Ready');
      expect(info.tone, StatusTone.success);
    });

    test('a metadata rejection keeps Ready but escalates to warning', () {
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 42, 'title': 'Some Movie'},
          'rejections': [
            {'reason': 'Not a preferred word upgrade', 'type': 'permanent'},
          ],
        }),
      );
      expect(info.label, 'Ready');
      expect(info.tone, StatusTone.warning);
      expect(info.semanticLabel, contains('warning'));
    });

    test('an unmatched file resolves to Needs match on warning', () {
      final info = manualImportItemStatus(ServiceKey.radarr, _item({}));
      expect(info.label, 'Needs match');
      expect(info.tone, StatusTone.warning);
    });

    test('a permanent identity rejection is amber, not red', () {
      // Changed: this used to resolve to StatusTone.error. Red is reserved for
      // a connection that did not answer. This one answered, and said it
      // cannot name the file, which is a fault the user clears by assigning an
      // identity. The neighbouring 'Needs match' branch was already amber for
      // the same affordance, and the facet chip over both calls the group
      // warning.
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'rejections': [
            {'reason': 'Unable to determine movie', 'type': 'permanent'},
          ],
        }),
      );
      expect(info.label, 'No match');
      expect(info.tone, StatusTone.warning);
      expect(info.detail, 'Unable to determine movie');
    });

    test('both classes of unmatched file resolve to the same tone', () {
      // The rule, not the colour: two tones over one fix sheet is what the
      // change above removed, so the two branches are asserted against each
      // other rather than against a constant.
      final permanent = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'rejections': [
            {'reason': 'Unable to determine movie', 'type': 'permanent'},
          ],
        }),
      );
      final plain = manualImportItemStatus(ServiceKey.radarr, _item({}));
      expect(permanent.tone, plain.tone);
    });

    test('a matched sample is neutral and says so', () {
      // A sample is matched as precisely as the rip beside it, so it used to
      // read "Ready", next to a checkbox the scan no longer ticks, which is a
      // row contradicting itself.
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 42, 'title': 'Some Movie'},
          'rejections': [
            {'reason': 'Sample', 'type': 'permanent'},
          ],
        }),
      );
      expect(info.label, 'Sample');
      expect(info.tone, StatusTone.neutral);
      expect(info.detail, 'Sample');
    });

    test('an already imported file resolves to the neutral tone', () {
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 42, 'title': 'Some Movie'},
          'movieFileId': 99,
        }),
      );
      expect(info.label, 'Imported');
      expect(info.tone, StatusTone.neutral);
    });
  });

  group('manualImportCommandStatus', () {
    ManualImportCommandStatus command(String status) =>
        ManualImportCommandStatus.fromJson({'id': 1, 'status': status});

    test('maps the lifecycle onto the closed tone vocabulary', () {
      // Changed: 'queued' used to resolve to StatusTone.warning. A command
      // waiting its turn is the service working as designed: informational,
      // the same tone the running one carries, and amber there put a fault
      // colour on every import posted while another was still running.
      expect(
        manualImportCommandStatus(command('queued')).tone,
        StatusTone.info,
      );
      expect(
        manualImportCommandStatus(command('started')).tone,
        StatusTone.info,
      );
      expect(
        manualImportCommandStatus(command('completed')).tone,
        StatusTone.success,
      );
      // Changed: the four terminal failures used to resolve to
      // StatusTone.error. The service answered and reported them, so the ones
      // nobody asked for are faults and the cancelled one is neutral.
      for (final status in const ['failed', 'aborted', 'orphaned']) {
        expect(
          manualImportCommandStatus(command(status)).tone,
          StatusTone.warning,
          reason: status,
        );
      }
      expect(
        manualImportCommandStatus(command('cancelled')).tone,
        StatusTone.neutral,
      );
      expect(manualImportCommandStatus(command('failed')).label, 'Failed');
    });

    test('no lifecycle state a user can wait through is a fault', () {
      // The rule the 'queued' fix encodes: amber means something went wrong,
      // and nothing in the first half of a command's life has.
      for (final status in const ['queued', 'started']) {
        expect(
          manualImportCommandStatus(command(status)).tone,
          isNot(StatusTone.warning),
          reason: '$status is progress, not a fault',
        );
      }
    });
  });
}
