import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_format.dart';

ProwlarrHistoryItem _item({
  required String eventType,
  bool successful = true,
}) => ProwlarrHistoryItem.fromJson({
  'id': 1,
  'eventType': eventType,
  'successful': successful,
  'date': '2026-09-16T10:00:00Z',
  'data': <String, dynamic>{},
});

void main() {
  group('prowlarrEventStyle', () {
    for (final (name, scheme) in <(String, ColorScheme)>[
      ('light', AppTheme.lightTheme().colorScheme),
      ('dark', AppTheme.darkTheme().colorScheme),
    ]) {
      group('on $name', () {
        test('a refused query is amber, never red', () {
          // Red belongs to a Prowlarr that did not answer. This one answered
          // and named which of its indexers refused — the canonical amber
          // fault of the whole app.
          final style = prowlarrEventStyle(
            _item(eventType: 'indexerQuery', successful: false),
            scheme,
          );
          expect(style.label, 'Failed');
          expect(style.color, statusToneColor(scheme, StatusTone.warning));
          expect(style.color, isNot(statusToneColor(scheme, StatusTone.error)));
        });

        test('a successful auth is informational, not a fault', () {
          // The failure arm above has already taken every unsuccessful event,
          // so this one is an indexer doing exactly what it should. It used to
          // paint amber, which left the real failure in the same list
          // indistinguishable from it.
          final style = prowlarrEventStyle(
            _item(eventType: 'indexerAuth'),
            scheme,
          );
          expect(style.color, statusToneColor(scheme, StatusTone.info));
          expect(
            style.color,
            isNot(statusToneColor(scheme, StatusTone.warning)),
          );
        });

        test('a grab resolves through the tone walk', () {
          expect(
            prowlarrEventStyle(
              _item(eventType: 'releaseGrabbed'),
              scheme,
            ).color,
            statusToneColor(scheme, StatusTone.success),
          );
        });

        test('a badge is sentence case, never a second uppercase voice', () {
          // The eyebrow is the only voice that uppercases. These badges repeat
          // on every row, and they used to read GRAB, QUERY and, for an event
          // nobody had named, the API identifier shouted in capitals.
          String label(String eventType) =>
              prowlarrEventStyle(_item(eventType: eventType), scheme).label;
          expect(label('releaseGrabbed'), 'Grab');
          expect(label('indexerQuery'), 'Query');
          expect(label('indexerAuth'), 'Auth');
          expect(label('indexerRss'), 'RSS');
          expect(label('indexerStatusChange'), 'Indexer status change');
        });
      });
    }
  });
}
