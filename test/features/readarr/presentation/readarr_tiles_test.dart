import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/widgets/readarr_tiles.dart';

void main() {
  group('ReadarrHistoryTile', () {
    testWidgets('is laid out on the spacing scale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: ReadarrHistoryTile(
              item: ReadarrHistoryItem(
                id: 1,
                eventType: 'grabbed',
                sourceTitle: 'Orbital',
                authorName: 'Samantha Harvey',
              ),
            ),
          ),
        ),
      );

      // The card sits in the page's gutter, one row-gap from the next, and
      // holds its content at the card padding of the Activity history rows.
      final outer = tester.widget<Padding>(
        find
            .ancestor(of: find.byType(Material), matching: find.byType(Padding))
            .first,
      );
      expect(
        outer.padding,
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
      );
      final card = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(Material),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(card.padding, const EdgeInsets.all(AppSpacing.md));
      // The gaps between the glyph, the words and the label.
      final gaps = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(Row),
              matching: find.byType(SizedBox),
            ),
          )
          .map((box) => box.width)
          .whereType<double>()
          .toList();
      expect(gaps, containsAll([AppSpacing.row, AppSpacing.sm]));
    });
  });

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
          // this function used to: grabbed and imported, the two events the
          // list shows most, so the Readarr history was the one place in the
          // app where the success green landed unwalked.
          // Neutral, and deliberately the same neutral the shared table
          // gives. This arm used to be blue on its own authority, so one
          // Readarr record wore two colours depending on which tab drew it.
          expect(
            readarrEventStyle('grabbed', scheme).color,
            statusToneColor(scheme, StatusTone.neutral),
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
          // default arm, which paints `onSurfaceVariant`, the backlog
          // treatment, given to the one row on the page that is not backlog.
          final incomplete = readarrEventStyle('bookImportIncomplete', scheme);
          expect(incomplete.color, statusToneColor(scheme, StatusTone.warning));
          expect(incomplete.color, isNot(scheme.onSurfaceVariant));
          // The table's wording, not this tile's. These are two different
          // events: a grab that never imported, and a book that imported with
          // files missing, and collapsing both to "Import failed" here made
          // the History tab say one thing where the Overview said two.
          expect(incomplete.label, 'Import incomplete');
          expect(
            readarrEventStyle('importFailed', scheme).label,
            'Import failed',
          );
          expect(
            readarrEventStyle('importFailed', scheme).color,
            statusToneColor(scheme, StatusTone.warning),
          );
        });

        test('a named event is spelled, never shouted camel-case', () {
          // The defect this function was: its default arm was
          // `eventType.toUpperCase()`, so `bookFileRenamed`, an event the
          // shared table has named since Readarr's arms landed, read
          // "BOOKFILERENAMED" on the History tab while the Overview, reading
          // the same record through the same table, read "Renamed".
          final renamed = readarrEventStyle('bookFileRenamed', scheme);
          expect(renamed.label, 'Renamed');
          expect(renamed.color, statusToneColor(scheme, StatusTone.neutral));

          final retagged = readarrEventStyle('bookFileRetagged', scheme);
          expect(retagged.label, 'Retagged');
          expect(retagged.color, statusToneColor(scheme, StatusTone.neutral));

          final ignored = readarrEventStyle('downloadIgnored', scheme);
          expect(ignored.label, 'Ignored');
        });

        test('this tile and the shared table cannot disagree', () {
          // The three surfaces derived this vocabulary independently, so the
          // guard is not "these strings are right" but "there is one table".
          for (final eventType in const [
            'grabbed',
            'bookFileImported',
            'downloadFolderImported',
            'authorFolderImported',
            'downloadFailed',
            'importFailed',
            'bookImportIncomplete',
            'bookFileDeleted',
            'bookFileRenamed',
            'bookFileRetagged',
            'downloadIgnored',
            'authorRenamed',
          ]) {
            final style = readarrEventStyle(eventType, scheme);
            expect(
              style.label,
              historyEventLabel(eventType),
              reason: 'label for $eventType',
            );
            expect(
              style.color,
              statusToneColor(scheme, historyEventTone(eventType)),
              reason: 'tone for $eventType',
            );
          }
        });

        test('an event nobody has classified is humanised, not shouted', () {
          // Still the default arm, but now the shared table's default: an
          // unnamed event is spelled out and left neutral, which is the right
          // answer for something nobody has classified. It is not a shout.
          final style = readarrEventStyle('authorRenamed', scheme);
          expect(style.label, 'Author renamed');
          expect(style.color, statusToneColor(scheme, StatusTone.neutral));
        });
      });
    }
  });
}
