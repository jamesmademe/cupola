import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/series/domain/sonarr_series_type.dart';

void main() {
  group('SonarrSeriesType', () {
    test('the wire value is what Sonarr stores, never the label', () {
      // The rule the write depends on: Sonarr matches the string exactly and
      // rejects "Anime". A refactor that made wireValue return `label` would
      // compile, pass a label-based test, and break every series-type write.
      for (final type in SonarrSeriesType.values) {
        expect(type.wireValue, type.wireValue.toLowerCase());
        expect(type.wireValue, isNot(type.label));
      }
      expect(
        SonarrSeriesType.values.map((t) => t.wireValue),
        containsAll(<String>['standard', 'daily', 'anime']),
      );
    });

    test('fromWire tolerates whatever casing the server used', () {
      expect(SonarrSeriesType.fromWire('anime'), SonarrSeriesType.anime);
      expect(SonarrSeriesType.fromWire('Anime'), SonarrSeriesType.anime);
      expect(SonarrSeriesType.fromWire('  DAILY '), SonarrSeriesType.daily);
    });

    test('an unknown value answers null instead of guessing', () {
      // The page prints whatever Sonarr said when this happens. Falling back to
      // `standard` would show a value the server is not using, on the one field
      // whose whole job is to explain why releases are not importing.
      expect(SonarrSeriesType.fromWire('sports'), isNull);
      expect(SonarrSeriesType.fromWire(''), isNull);
      expect(SonarrSeriesType.fromWire(null), isNull);
    });

    test('every type says what choosing it changes', () {
      // The picker prints the description under the label and a screen reader
      // reads it as the option's hint, so an empty one leaves a blind user
      // choosing between three words.
      for (final type in SonarrSeriesType.values) {
        expect(type.label, isNotEmpty);
        expect(type.description, isNotEmpty);
      }
    });
  });
}
