import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_tab_screens.dart';

import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  transmissionUrl: 'https://transmission.test',
  transmissionUsername: 'user',
  transmissionPassword: 'secret',
);

void main() {
  testWidgets('both tabs stop before providers when not configured', (
    tester,
  ) async {
    var torrentReads = 0;
    var sessionReads = 0;
    final overrides = <Override>[
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
      transmissionTorrentsProvider.overrideWith((ref) async {
        torrentReads++;
        return const [];
      }),
      transmissionSessionProvider.overrideWith((ref) async {
        sessionReads++;
        return _session();
      }),
    ];

    for (final screen in const <Widget>[
      TransmissionLabelsScreen(),
      TransmissionSessionScreen(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: overrides,
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    }

    expect(torrentReads, 0);
    expect(sessionReads, 0);
  });

  // RPC 16 is Transmission 3.00, which is where `labels` landed, on
  // `torrent-get` and `torrent-set` together. It is the *oldest* daemon that
  // can be edited, and it used to be refused.
  testWidgets('labels are editable from RPC 16, where they landed', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const TransmissionLabelsScreen(),
      overrides: [
        transmissionTorrentsProvider.overrideWith(
          (ref) async => [
            _torrent(labels: const ['movies']),
          ],
        ),
        transmissionSessionProvider.overrideWith(
          (ref) async => _session(rpcVersion: 16),
        ),
      ],
    );

    expect(find.text('movies\u00A0· 1'), findsOneWidget);
    expect(find.textContaining('does not support labels'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('labels are readable but not editable before RPC 16', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const TransmissionLabelsScreen(),
      overrides: [
        transmissionTorrentsProvider.overrideWith(
          (ref) async => [
            _torrent(labels: const ['movies']),
          ],
        ),
        transmissionSessionProvider.overrideWith(
          (ref) async => _session(rpcVersion: 15),
        ),
      ],
    );

    expect(find.text('movies\u00A0· 1'), findsOneWidget);
    expect(find.textContaining('does not support labels'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('label editor trims and deduplicates one label per line', (
    tester,
  ) async {
    final client = _RecordingClient();
    final torrent = _torrent(labels: const ['old']);
    await _pump(
      tester,
      screen: const TransmissionLabelsScreen(),
      overrides: [
        transmissionClientProvider.overrideWith((ref) => client),
        transmissionTorrentsProvider.overrideWith((ref) async => [torrent]),
        transmissionSessionProvider.overrideWith((ref) async => _session()),
      ],
    );

    await tester.tap(
      find.byKey(ValueKey('transmission-labels-edit-${torrent.rpcId}')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transmission-labels-field')),
      ' movies \n4k\nmovies\n',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(client.labelWrites, hasLength(1));
    expect(client.labelWrites.single.ids, [torrent.rpcId]);
    expect(client.labelWrites.single.labels, ['movies', '4k']);
    expect(find.text('Labels updated'), findsOneWidget);
  });

  // The two halves of the same rule. A field the daemon never sent is an em
  // dash; a field it reported as zero is a zero. Collapsing them, which is
  // what a non-nullable `parseInt` default does: it states a figure nobody gave.
  testWidgets('a session field the daemon omitted reads an em dash', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const TransmissionSessionScreen(),
      overrides: [
        transmissionSessionProvider.overrideWith(
          (ref) async =>
              _session(version: '', omit: const {'peer-port', 'rpc-version'}),
        ),
      ],
    );

    expect(find.semantics.byLabel('Peer port, —'), findsOneWidget);
    expect(find.textContaining('RPC —'), findsOneWidget);
  });

  testWidgets('a session field the daemon reported as zero reads zero', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const TransmissionSessionScreen(),
      overrides: [
        transmissionSessionProvider.overrideWith(
          (ref) async => _session(blocklistSize: 0),
        ),
      ],
    );

    await tester.scrollUntilVisible(
      find.text('Rules reported'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.semantics.byLabel('Rules reported, 0'), findsOneWidget);
  });

  testWidgets('session toggle writes only the selected preference', (
    tester,
  ) async {
    final client = _RecordingClient();
    await _pump(
      tester,
      screen: const TransmissionSessionScreen(),
      overrides: [
        transmissionClientProvider.overrideWith((ref) => client),
        transmissionSessionProvider.overrideWith(
          (ref) async => _session(blocklistEnabled: true),
        ),
      ],
    );

    await tester.scrollUntilVisible(
      find.text('Use blocklist'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Use blocklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use blocklist'));
    await tester.pumpAndSettle();

    expect(client.sessionWrites, [
      {'blocklist-enabled': false},
    ]);
    expect(find.text('Blocklist preference updated'), findsOneWidget);
  });

  group('the number dialog owns its controller', () {
    // A `showDialog` future completes as the route pops, well before the exit
    // transition ends. A controller disposed after that `await` was gone while
    // the field was still on screen fading out.
    Future<TextEditingController> openPeerPort(
      WidgetTester tester,
      _RecordingClient client,
    ) async {
      await _pump(
        tester,
        screen: const TransmissionSessionScreen(),
        overrides: [
          transmissionClientProvider.overrideWith((ref) => client),
          transmissionSessionProvider.overrideWith((ref) async => _session()),
        ],
      );
      await tester.tap(find.text('Peer port'));
      await tester.pumpAndSettle();
      return tester
          .widget<TextField>(
            find.byKey(const ValueKey('transmission-session-number-field')),
          )
          .controller!;
    }

    bool isDisposed(TextEditingController controller) {
      try {
        controller.addListener(() {});
        return false;
      } on FlutterError {
        return true;
      }
    }

    for (final (label, tapped, saves) in const [
      ('Save', 'Save', true),
      ('Cancel', 'Cancel', false),
    ]) {
      testWidgets('$label leaves the field alive until the route is gone', (
        tester,
      ) async {
        final client = _RecordingClient();
        final controller = await openPeerPort(tester, client);
        await tester.enterText(
          find.byKey(const ValueKey('transmission-session-number-field')),
          '6881',
        );

        await tester.tap(find.text(tapped));
        // The route has popped and is fading out: the field is still drawn.
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byKey(const ValueKey('transmission-session-number-field')),
          findsOneWidget,
        );
        expect(isDisposed(controller), isFalse);
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('transmission-session-number-field')),
          findsNothing,
        );
        expect(isDisposed(controller), isTrue);
        expect(client.sessionWrites, saves ? hasLength(1) : isEmpty);
      });
    }

    testWidgets('a value out of range keeps the dialog and says so', (
      tester,
    ) async {
      final client = _RecordingClient();
      await openPeerPort(tester, client);
      await tester.enterText(
        find.byKey(const ValueKey('transmission-session-number-field')),
        '70000',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a value in range'), findsOneWidget);
      expect(client.sessionWrites, isEmpty);
    });
  });

  testWidgets('session failure renders Retry rather than fabricated values', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const TransmissionSessionScreen(),
      overrides: [
        transmissionSessionProvider.overrideWith(
          (ref) => Future.error(Exception('offline')),
        ),
      ],
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}

class _RecordingClient extends TransmissionClient {
  _RecordingClient() : super(url: 'https://transmission.test');

  final List<({List<String> ids, List<String> labels})> labelWrites = [];
  final List<Map<String, Object>> sessionWrites = [];

  @override
  Future<void> setLabels(List<String> ids, List<String> labels) async {
    labelWrites.add((ids: [...ids], labels: [...labels]));
  }

  @override
  Future<void> setSessionPreferences({
    int? peerPort,
    bool? peerPortRandomOnStart,
    bool? portForwardingEnabled,
    String? encryption,
    int? peerLimitGlobal,
    int? peerLimitPerTorrent,
    double? seedRatioLimit,
    bool? seedRatioLimited,
    int? idleSeedingLimitMinutes,
    bool? idleSeedingLimitEnabled,
    bool? blocklistEnabled,
    bool? downloadQueueEnabled,
    int? downloadQueueSize,
    bool? seedQueueEnabled,
    int? seedQueueSize,
    bool? startAddedTorrents,
    bool? renamePartialFiles,
    int? cacheSizeMb,
  }) async {
    final values = <String, Object>{};
    void add(String key, Object? value) {
      if (value != null) values[key] = value;
    }

    add('peer-port', peerPort);
    add('peer-port-random-on-start', peerPortRandomOnStart);
    add('port-forwarding-enabled', portForwardingEnabled);
    add('encryption', encryption);
    add('peer-limit-global', peerLimitGlobal);
    add('peer-limit-per-torrent', peerLimitPerTorrent);
    add('seedRatioLimit', seedRatioLimit);
    add('seedRatioLimited', seedRatioLimited);
    add('idle-seeding-limit', idleSeedingLimitMinutes);
    add('idle-seeding-limit-enabled', idleSeedingLimitEnabled);
    add('blocklist-enabled', blocklistEnabled);
    add('download-queue-enabled', downloadQueueEnabled);
    add('download-queue-size', downloadQueueSize);
    add('seed-queue-enabled', seedQueueEnabled);
    add('seed-queue-size', seedQueueSize);
    add('start-added-torrents', startAddedTorrents);
    add('rename-partial-files', renamePartialFiles);
    add('cache-size-mb', cacheSizeMb);
    sessionWrites.add(values);
  }
}

TransmissionTorrent _torrent({List<String> labels = const []}) =>
    TransmissionTorrent.fromJson({
      'id': 7,
      'hashString': 'hash-7',
      'name': 'A Torrent',
      'status': 6,
      'percentDone': 1.0,
      'labels': labels,
    });

/// A session document, with [omit] naming the keys a daemon did not send.
TransmissionSession _session({
  String version = '4.0.6',
  int rpcVersion = 17,
  int peerPort = 51413,
  int blocklistSize = 1200,
  bool blocklistEnabled = false,
  Set<String> omit = const {},
}) => TransmissionSession.fromJson({
  for (final entry in <String, dynamic>{
    'version': version,
    'rpc-version': rpcVersion,
    'download-dir': '/downloads',
    'incomplete-dir': '/incomplete',
    'incomplete-dir-enabled': true,
    'alt-speed-enabled': false,
    'speed-limit-down': 4096,
    'speed-limit-down-enabled': true,
    'speed-limit-up': 1024,
    'speed-limit-up-enabled': false,
    'peer-port': peerPort,
    'peer-port-random-on-start': false,
    'port-forwarding-enabled': true,
    'encryption': 'preferred',
    'peer-limit-global': 400,
    'peer-limit-per-torrent': 60,
    'seedRatioLimit': 2.0,
    'seedRatioLimited': true,
    'idle-seeding-limit': 30,
    'idle-seeding-limit-enabled': true,
    'blocklist-enabled': blocklistEnabled,
    'blocklist-size': blocklistSize,
    'download-queue-enabled': true,
    'download-queue-size': 5,
    'seed-queue-enabled': true,
    'seed-queue-size': 10,
    'start-added-torrents': true,
    'rename-partial-files': true,
    'cache-size-mb': 16,
  }.entries)
    if (!omit.contains(entry.key)) entry.key: entry.value,
});

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _configured),
        ...overrides,
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}
