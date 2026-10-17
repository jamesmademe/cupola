import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

void main() {
  group('downloadRowValue', () {
    test('replaces visual dot separators with commas', () {
      expect(
        downloadRowValue(
          subtitle: 'Movie\u00A0· Furiosa.2024.2160p.WEB-DL-GROUP',
          percent: 75,
          warning: null,
        ),
        '75 percent downloaded, Movie, Furiosa.2024.2160p.WEB-DL-GROUP',
      );
    });

    test("leads with the client's own reason, not the word 'Warning'", () {
      // A bare "Warning" named that something was wrong without saying what,
      // while the reason sat unused in the model.
      expect(
        downloadRowValue(
          subtitle: 'Movie',
          percent: 40,
          warning: 'Download stalled',
        ),
        'Download stalled, 40 percent downloaded, Movie',
      );
    });

    test('omits progress entirely when the client reports none', () {
      // The row paints nothing in that slot either.
      expect(
        downloadRowValue(subtitle: 'Movie', percent: null, warning: null),
        'Movie',
      );
    });
  });

  group('serviceMatrixCellValue', () {
    test('leads with reachability, then the signal, then the host', () {
      expect(
        serviceMatrixCellValue(
          statusLabel: 'Online',
          signalSpoken: 'Missing 12',
          host: 'radarr.local:7878',
        ),
        'Online, Missing 12, radarr.local:7878',
      );
    });

    test('drops the signal while the metric is still resolving', () {
      expect(
        serviceMatrixCellValue(
          statusLabel: 'Checking',
          signalSpoken: null,
          host: 'radarr.local:7878',
        ),
        'Checking, radarr.local:7878',
      );
    });

    test('says only the state when a service has no host configured', () {
      expect(
        serviceMatrixCellValue(
          statusLabel: 'Offline',
          signalSpoken: null,
          host: '',
        ),
        'Offline',
      );
    });
  });

  group('serviceDomainBandValue', () {
    test('a band announces its size and nothing else', () {
      // It used to carry the offline services too, because a folded band was a
      // strip of bare glyphs and an unlit tile says nothing to a screen reader.
      // The compact cards that replaced the strip are labelled nodes of their
      // own, so repeating it here would say "Lidarr did not answer." twice on
      // the way into the band.
      expect(serviceDomainBandValue(serviceCount: 6), '6 services');
    });

    test('agrees in number', () {
      expect(serviceDomainBandValue(serviceCount: 1), '1 service');
    });
  });

  group('servicesSectionOfflineMessage', () {
    test('shares the band sentence but names fewer sources', () {
      // It sits in a 176pt rail as a footnote to a band the user has already
      // scrolled past, not across the full width as the primary warning.
      expect(
        servicesSectionOfflineMessage(const ['Radarr', 'Sonarr', 'Lidarr']),
        "Radarr, Sonarr and 1 other did not answer.",
      );
    });
  });

  group('servicesAlertBandMessage', () {
    test('a single offender is named on its own', () {
      expect(servicesAlertBandMessage(['Dockge']), "Dockge did not answer.");
    });

    test('two are joined with "and", not a trailing comma', () {
      expect(
        servicesAlertBandMessage(['Dockge', 'TrueNAS']),
        "Dockge and TrueNAS did not answer.",
      );
    });

    test('three are listed in full', () {
      expect(
        servicesAlertBandMessage(['Dockge', 'TrueNAS', 'Unraid']),
        "Dockge, TrueNAS and Unraid did not answer.",
      );
    });

    test('more than three fold into "and n others"', () {
      expect(
        servicesAlertBandMessage([
          'Dockge',
          'TrueNAS',
          'Unraid',
          'Bazarr',
          'Prowlarr',
        ]),
        "Dockge, TrueNAS, Unraid and 2 others did not answer.",
      );
    });

    test('exactly one hidden offender is singular', () {
      expect(
        servicesAlertBandMessage(['Dockge', 'TrueNAS', 'Unraid', 'Bazarr']),
        "Dockge, TrueNAS, Unraid and 1 other did not answer.",
      );
    });

    test('an empty list produces no sentence at all', () {
      // The band renders nothing in this state; a stray "did not answer."
      // would be worse than silence.
      expect(servicesAlertBandMessage([]), isEmpty);
      expect(servicesAlertBandMessage(['', '   ']), isEmpty);
    });
  });

  test('a band away from home counts the services only at home once', () {
    expect(
      serviceDomainHealthLine(
        clean: 0,
        total: 2,
        qualifiers: const [
          'Radarr needs a look',
          'Sonarr needs a look',
          'Lidarr checking',
        ],
        onlyAtHome: 4,
      ),
      '0 of 2 clean\u00A0· Radarr needs a look\u00A0· Sonarr needs a look\u00A0· 1 other\u00A0· '
      '4 only at home',
    );
  });
}
