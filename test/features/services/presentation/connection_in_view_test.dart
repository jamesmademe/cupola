/// The connection a visit to a service reads, and what moves it.
///
/// A visit is one stay inside a service's own pages. Its scope sees the
/// location the router shows each time anything inside the service navigates,
/// and these cases pin what it does with the `?i=` it finds there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/presentation/connection_in_view.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _home = ServiceInstance(
  id: 'jellyfin',
  service: ServiceKey.jellyfin,
  label: 'Home',
  url: 'https://home.lan:8096',
  credential: 'k',
);
const _cabin = ServiceInstance(
  id: 'jellyfin-cabin01',
  service: ServiceKey.jellyfin,
  label: 'Cabin',
  url: 'https://cabin.lan:8096',
  credential: 'k',
);
const _plex = ServiceInstance(
  id: 'plex',
  service: ServiceKey.plex,
  url: 'https://plex.lan:32400',
  credential: 'k',
);

const _twoJellyfin = SettingsModel(instances: [_home, _cabin, _plex]);

/// The settings the test can change under the scope, as the app's own can.
class _Settings extends Notifier<SettingsModel> {
  @override
  SettingsModel build() => _twoJellyfin;

  void set(SettingsModel settings) => state = settings;
}

final _settingsHolder = NotifierProvider<_Settings, SettingsModel>(
  _Settings.new,
);

/// What the probe under the scope last saw.
class _Seen {
  ConnectionInView? view;
}

class _Host extends StatefulWidget {
  const _Host({required this.location, required this.seen});

  final ValueNotifier<Uri> location;
  final _Seen seen;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Uri>(
    valueListenable: widget.location,
    builder: (context, location, _) => ConnectionInViewScope(
      service: ServiceKey.jellyfin,
      location: location,
      child: Column(
        children: [
          Builder(
            builder: (context) {
              widget.seen.view = ConnectionInView.maybeOf(
                context,
                ServiceKey.jellyfin,
              );
              return const SizedBox.shrink();
            },
          ),
          const InstanceLensBadge(service: ServiceKey.jellyfin),
        ],
      ),
    ),
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required ValueNotifier<Uri> location,
  required _Seen seen,
  String lens = 'jellyfin',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => ref.watch(_settingsHolder)),
      initialActiveInstancesProvider.overrideWithValue({
        ServiceKey.jellyfin: lens,
      }),
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: _Host(location: location, seen: seen),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

String _lens(ProviderContainer container) =>
    container.read(activeInstanceProvider(ServiceKey.jellyfin))!.id;

Finder get _badge => find.byType(InstanceLensBadge);

/// The words the badge draws, or null when it draws nothing.
String? _badgeSays(WidgetTester tester) {
  final texts = find.descendant(of: _badge, matching: find.byType(Text));
  return texts.evaluate().isEmpty
      ? null
      : tester.widget<Text>(texts.first).data;
}

Uri _at(String path, [String? i]) =>
    Uri(path: path, queryParameters: i == null ? null : {'i': i});

void main() {
  test('a link names a connection only if it is the service\'s', () {
    expect(
      namedConnectionOf(_twoJellyfin, ServiceKey.jellyfin, 'jellyfin-cabin01'),
      'jellyfin-cabin01',
    );
    // Another service's, a removed one, a blank one and none.
    expect(namedConnectionOf(_twoJellyfin, ServiceKey.jellyfin, 'plex'), '');
    expect(namedConnectionOf(_twoJellyfin, ServiceKey.jellyfin, 'gone'), '');
    expect(namedConnectionOf(_twoJellyfin, ServiceKey.jellyfin, ' '), '');
    expect(namedConnectionOf(_twoJellyfin, ServiceKey.jellyfin, null), '');
    expect(
      namedConnectionOf(_twoJellyfin, ServiceKey.plex, 'jellyfin-cabin01'),
      '',
    );
    // One with no address yet cannot be asked: the form between "add another"
    // and typing it.
    expect(
      namedConnectionOf(
        const SettingsModel(
          instances: [
            _home,
            ServiceInstance(
              id: 'jellyfin-blank11',
              service: ServiceKey.jellyfin,
              label: 'Half done',
            ),
          ],
        ),
        ServiceKey.jellyfin,
        'jellyfin-blank11',
      ),
      '',
    );
  });

  testWidgets('a location that names a connection puts it in view, and the '
      'badge names it, with the lens left where it was', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    final container = await _pump(tester, location: location, seen: seen);

    expect(seen.view?.instanceId, _cabin.id);
    expect(_badgeSays(tester), 'Cabin');
    expect(_lens(container), 'jellyfin');
  });

  testWidgets('a location with no ?i= keeps what the visit has in view', (
    tester,
  ) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    await _pump(tester, location: location, seen: seen);

    location.value = _at('/jellyfin/libraries');
    await tester.pumpAndSettle();
    expect(seen.view?.instanceId, _cabin.id);

    location.value = _at('/jellyfin/users');
    await tester.pumpAndSettle();
    expect(seen.view?.instanceId, _cabin.id);
    expect(_badgeSays(tester), 'Cabin');
  });

  testWidgets('a visit opened with no ?i= reads the lens and the badge names '
      'it', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/overview'));
    final seen = _Seen();
    await _pump(tester, location: location, seen: seen);

    expect(seen.view?.instanceId, isEmpty);
    expect(_badgeSays(tester), 'Home');
  });

  testWidgets('a ?i= that names no connection of the service reads the lens', (
    tester,
  ) async {
    for (final dead in ['gone', 'plex', ' ']) {
      final location = ValueNotifier(_at('/jellyfin/overview', dead));
      final seen = _Seen();
      await _pump(tester, location: location, seen: seen);

      expect(seen.view?.instanceId, isEmpty, reason: dead);
      expect(_badgeSays(tester), 'Home', reason: dead);
    }
  });

  testWidgets('a connection removed from the settings while in view reads as '
      'the lens', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    final container = await _pump(tester, location: location, seen: seen);
    expect(seen.view?.instanceId, _cabin.id);

    container
        .read(_settingsHolder.notifier)
        .set(const SettingsModel(instances: [_home, _plex]));
    await tester.pumpAndSettle();

    expect(seen.view?.instanceId, isEmpty);
  });

  testWidgets('the lens sheet puts the choice in view, and moves the lens '
      'only when it is another connection', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    final container = await _pump(tester, location: location, seen: seen);

    // The connection in view is the ticked row, and choosing the lens' own
    // makes it the one in view.
    await tester.tap(_badge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(seen.view?.instanceId, 'jellyfin');
    expect(_badgeSays(tester), 'Home');
    expect(_lens(container), 'jellyfin');

    // Choosing the other moves both.
    await tester.tap(_badge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabin'));
    await tester.pumpAndSettle();

    expect(seen.view?.instanceId, _cabin.id);
    expect(_badgeSays(tester), 'Cabin');
    expect(_lens(container), _cabin.id);
  });

  testWidgets('choosing the connection in view that is not the lens makes it '
      'the lens too', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    final container = await _pump(tester, location: location, seen: seen);
    expect(_lens(container), 'jellyfin');

    await tester.tap(_badge);
    await tester.pumpAndSettle();
    // The badge says Cabin too: the sheet's row is the one drawn last.
    await tester.tap(find.text('Cabin').last);
    await tester.pumpAndSettle();

    expect(seen.view?.instanceId, _cabin.id);
    expect(_lens(container), _cabin.id);
  });

  testWidgets('a restored location is not a new link: it does not take the '
      'visit back from a choice made since', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    await _pump(tester, location: location, seen: seen);

    // Overview through the bar, then the lens sheet picks Home.
    location.value = _at('/jellyfin/overview');
    await tester.pumpAndSettle();
    await tester.tap(_badge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(seen.view?.instanceId, 'jellyfin');

    // `goBranch` puts Activity back where it was left, `?i=` and all.
    location.value = _at('/jellyfin/activity', _cabin.id);
    await tester.pumpAndSettle();
    expect(seen.view?.instanceId, 'jellyfin');
    expect(_badgeSays(tester), 'Home');
  });

  testWidgets('a link that names another connection moves the visit, and so '
      'does one that names the first again', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    await _pump(tester, location: location, seen: seen);

    location.value = _at('/jellyfin/activity', 'jellyfin');
    await tester.pumpAndSettle();
    expect(seen.view?.instanceId, 'jellyfin');

    location.value = _at('/jellyfin/activity', _cabin.id);
    await tester.pumpAndSettle();
    expect(seen.view?.instanceId, _cabin.id);
  });

  testWidgets('what is in view is for that service alone, and for the visit '
      'alone', (tester) async {
    final location = ValueNotifier(_at('/jellyfin/activity', _cabin.id));
    final seen = _Seen();
    await _pump(tester, location: location, seen: seen);

    final inside = tester.element(find.byType(InstanceLensBadge));
    expect(ConnectionInView.maybeOf(inside, ServiceKey.jellyfin), isNotNull);
    // Plex has no visit under here, so it reads its own lens.
    expect(ConnectionInView.maybeOf(inside, ServiceKey.plex), isNull);

    // A new visit is a new scope: nothing carries over.
    await tester.pumpWidget(const SizedBox.shrink());
    final fresh = _Seen();
    await _pump(
      tester,
      location: ValueNotifier(_at('/jellyfin/overview')),
      seen: fresh,
    );
    expect(fresh.view?.instanceId, isEmpty);
  });
}
