import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/presentation/request_form_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/approve_request_sheet.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _radarr = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 0,
  name: 'Radarr',
  isDefault: true,
  activeProfileId: 4,
  activeProfileName: 'HD-1080p',
  activeDirectory: '/movies',
);
const _spare = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 2,
  name: 'Radarr spare',
  activeProfileId: 7,
  activeDirectory: '/spare',
);
const _uhd = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 1,
  name: 'Radarr 4K',
  is4k: true,
  isDefault: true,
);

/// Anna's request names nothing: it goes with the default server's own.
const _request = SeerrRequest(
  id: 7,
  status: RequestStatus.pendingApproval,
  createdAt: '2026-10-21T10:00:00Z',
  type: 'movie',
);

final _target = SeerrApproveTarget.of(
  _request,
  servers: const [_radarr, _spare, _uhd],
);

Future<List<ApproveChoice?>> _pump(WidgetTester tester) async {
  final chosen = <ApproveChoice?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        seerrServerChoicesProvider.overrideWith(
          (ref, source) async => (
            profiles: const [
              QualityProfileOption(id: 4, name: 'HD-1080p'),
              QualityProfileOption(id: 6, name: 'Ultra-HD'),
              QualityProfileOption(id: 7, name: 'Any'),
            ],
            folders: const [
              RootFolderOption(path: '/movies', freeSpace: 12400000000000),
              RootFolderOption(path: '/spare'),
            ],
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => chosen.add(
                  await showApproveRequestSheet(
                    context,
                    instanceId: 'seerr',
                    title: 'Charge',
                    request: _request,
                    target: _target,
                    servers: const [_radarr, _spare, _uhd],
                    connections: const [],
                    connectionTitle: (connection) => connection.service.title,
                  ),
                ),
                child: const Text('Decide'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Decide'));
  await tester.pumpAndSettle();
  return chosen;
}

void main() {
  group('approveChoiceChanges', () {
    test('the defaults the sheet opened on are no change, though the '
        'request names none of them', () {
      expect(
        approveChoiceChanges(_target, (
          server: _radarr,
          profileId: 4,
          rootFolder: '/movies',
        )),
        isFalse,
      );
    });

    test('another server, profile or folder is one', () {
      expect(
        approveChoiceChanges(_target, (
          server: _spare,
          profileId: 4,
          rootFolder: '/movies',
        )),
        isTrue,
      );
      expect(
        approveChoiceChanges(_target, (
          server: _radarr,
          profileId: 6,
          rootFolder: '/movies',
        )),
        isTrue,
      );
      expect(
        approveChoiceChanges(_target, (
          server: _radarr,
          profileId: 4,
          rootFolder: '/spare',
        )),
        isTrue,
      );
    });
  });

  testWidgets('the sheet opens on where Seerr would send it, offers only '
      'servers of its copy, and answers what was chosen', (tester) async {
    final chosen = await _pump(tester);

    expect(find.text('Approve Charge'), findsOneWidget);
    expect(
      find.text(
        'Charge goes to Radarr and starts downloading. Cupola '
        'has no connection to that server.',
      ),
      findsOneWidget,
    );
    // The 4K server takes 4K requests only.
    expect(find.text('Radarr spare'), findsOneWidget);
    expect(find.text('Radarr 4K'), findsNothing);
    expect(find.text('HD-1080p'), findsOneWidget);
    expect(find.text('/movies'), findsOneWidget);

    await tester.tap(find.text('Quality profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ultra-HD'));
    await tester.pumpAndSettle();
    expect(find.text('Ultra-HD'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
    await tester.pumpAndSettle();
    expect(chosen, hasLength(1));
    final choice = chosen.single!;
    expect(choice.server.id, 0);
    expect(choice.profileId, 6);
    expect(choice.rootFolder, '/movies');
  });

  testWidgets('another server brings its own profile and folder', (
    tester,
  ) async {
    final chosen = await _pump(tester);

    await tester.tap(find.text('Radarr spare'));
    await tester.pumpAndSettle();
    expect(find.text('/spare'), findsOneWidget);
    expect(
      find.text(
        'Charge goes to Radarr spare and starts downloading. '
        'Cupola has no connection to that server.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
    await tester.pumpAndSettle();
    final choice = chosen.single!;
    expect(choice.server.id, 2);
    expect(choice.profileId, 7);
    expect(choice.rootFolder, '/spare');
  });

  testWidgets('closed, the sheet answers nothing', (tester) async {
    final chosen = await _pump(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(chosen, [null]);
  });
}
