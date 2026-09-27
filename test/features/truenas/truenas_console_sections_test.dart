import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';

void main() {
  group('the console rail — decision 36', () {
    test('nine doors, not ten', () {
      expect(trueNasSections, hasLength(9));
    });

    test('Containers and Virtual Machines are one Virtualization door', () {
      final titles = trueNasSections.map((s) => s.title).toList();
      expect(titles, contains('Virtualization'));
      expect(titles, isNot(contains('Containers')));
      expect(titles, isNot(contains('Virtual machines')));
    });

    test('that one door still owns both of the old paths', () {
      // Until `router.dart` collapses them into one `virtualization?kind=`
      // route, a `/vms` deep link has to light the Virtualization row — before
      // this, it lit nothing at all.
      final virt = trueNasSections.singleWhere(
        (s) => s.title == 'Virtualization',
      );
      expect(
        virt.routes,
        containsAll([
          ServiceRoutes.truenasContainers,
          ServiceRoutes.truenasVms,
        ]),
      );
    });

    test('Apps sits before Virtualization, as the design orders them', () {
      final titles = trueNasSections.map((s) => s.title).toList();
      expect(
        titles.indexOf('Apps'),
        lessThan(titles.indexOf('Virtualization')),
      );
      expect(
        titles.indexOf('Virtualization'),
        lessThan(titles.indexOf('Data protection')),
      );
    });

    test('every door owns at least its own route, and no route twice', () {
      final seen = <String>{};
      for (final section in trueNasSections) {
        expect(section.routes.first, section.route);
        for (final route in section.routes) {
          expect(
            seen.add(route),
            isTrue,
            reason: '$route is claimed by two rail rows',
          );
        }
      }
    });
  });

  group('the dataset deep link', () {
    test('a ZFS id with slashes survives the round trip', () {
      // ZFS ids are paths (`tank/media/movies`). As a path *segment* the route
      // would split into three and match nothing, which is why the detail takes
      // a query parameter — and why a future tidy-up to `/detail/:id` must fail
      // here rather than in the field.
      final link = ServiceRoutes.truenasDataset('tank/media/movies');

      expect(link, startsWith(ServiceRoutes.truenasDatasetDetail));
      expect(Uri.parse(link).queryParameters['id'], 'tank/media/movies');
      // Encoded, so the slashes never reach the path matcher.
      expect(
        link.substring(ServiceRoutes.truenasDatasetDetail.length),
        isNot(contains('/')),
      );
    });

    test('an empty id builds no query at all, so the redirect can fire', () {
      expect(
        ServiceRoutes.truenasDataset(''),
        ServiceRoutes.truenasDatasetDetail,
      );
    });
  });
}
