import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/readarr/presentation/widgets/readarr_tiles.dart';

void main() {
  group('readarrEventStyle', () {
    /// Both schemes, because the whole point of walking a tone is that the
    /// answer depends on the ground.
    for (final (name, scheme) in <(String, ColorScheme)>[
      ('light', AppTheme.lightTheme().colorScheme),
      ('dark', AppTheme.darkTheme().colorScheme),
    ]) {
      group('on $name', () {
        test('every event resolves through the tone walk', () {
          // The rule: no surface paints a palette constant raw. Two arms of
          // this function used to — grabbed and imported, the two events the
          // list shows most — so the Readarr history was the one place in the
          // app where the success green landed unwalked.
          expect(
            readarrEventStyle('grabbed', scheme).color,
            statusToneColor(scheme, StatusTone.info),
          );
          expect(
            readarrEventStyle('bookFileImported', scheme).color,
            statusToneColor(scheme, StatusTone.success),
          );
          expect(
            readarrEventStyle('downloadFolderImported', scheme).color,
            statusToneColor(scheme, StatusTone.success),
          );
          expect(
            readarrEventStyle('bookFileDeleted', scheme).color,
            statusToneColor(scheme, StatusTone.neutral),
          );
          expect(
            readarrEventStyle('downloadFailed', scheme).color,
            statusToneColor(scheme, StatusTone.warning),
          );
        });

        test('a failed download is amber, never red', () {
          // Red is reserved for a Readarr that did not answer. A grab Readarr
          // told us about failing is a fault it reported, and the four arrs had
          // five separate copies of the failed-history-is-red pattern.
          final failed = readarrEventStyle('downloadFailed', scheme).color;
          expect(failed, statusToneColor(scheme, StatusTone.warning));
          expect(failed, isNot(statusToneColor(scheme, StatusTone.error)));
        });

        test('a deleted file is backlog, not a fault', () {
          // Deleting is a choice. It belongs with missing and paused in the
          // neutral arm, and it must not borrow the fault colour.
          final deleted = readarrEventStyle('bookFileDeleted', scheme).color;
          expect(deleted, isNot(statusToneColor(scheme, StatusTone.warning)));
          expect(deleted, isNot(statusToneColor(scheme, StatusTone.error)));
        });

        test('an import fault is amber, not the grey of an unknown event', () {
          // `bookImportIncomplete` is Readarr's own spelling and the failure a
          // book library actually suffers. It used to fall through to the
          // default arm, which paints `onSurfaceVariant` — the backlog
          // treatment, given to the one row on the page that is not backlog.
          final incomplete = readarrEventStyle('bookImportIncomplete', scheme);
          expect(incomplete.color, statusToneColor(scheme, StatusTone.warning));
          expect(incomplete.color, isNot(scheme.onSurfaceVariant));
          expect(incomplete.label, 'IMPORT FAILED');
          expect(
            readarrEventStyle('importFailed', scheme).color,
            statusToneColor(scheme, StatusTone.warning),
          );
        });

        test('an event Readarr invented prints its own name', () {
          final style = readarrEventStyle('authorRenamed', scheme);
          expect(style.label, 'AUTHORRENAMED');
          expect(style.color, scheme.onSurfaceVariant);
        });
      });
    }
  });
}
