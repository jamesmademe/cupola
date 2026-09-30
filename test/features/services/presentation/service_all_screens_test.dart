import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/content_card.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/fake_services.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('all requests renders filter chips and compact request rows', (
    tester,
  ) async {
    await _pumpAllRequests(tester);
    await _pumpAsyncContent(tester);

    expect(find.text('All requests'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('A Quiet Place'), findsOneWidget);
    expect(find.text('sarah'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    // Sentence case: a per-row pill is a dense label, not an eyebrow.
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Partially available'), findsOneWidget);
    expect(_contentCardWithImage('/quiet-place.jpg'), findsOneWidget);
  });

  group('filter chips', () {
    testWidgets('selecting a bucket narrows the list', (tester) async {
      await _pumpAllRequests(tester);
      await _pumpAsyncContent(tester);

      // Both fixtures are past approval, so Approved keeps both...
      await tester.tap(find.text('Approved'));
      await _settle(tester);

      expect(find.text('A Quiet Place'), findsOneWidget);
      expect(find.text('Shogun'), findsOneWidget);

      // ...and Pending keeps neither, because media availability overrides the
      // request status: the available one reports `available`, not `pending`.
      await tester.tap(find.text('Waiting for approval'));
      await _settle(tester);

      expect(find.text('A Quiet Place'), findsNothing);
      expect(find.text('Shogun'), findsNothing);
      expect(find.text('No requests waiting for approval'), findsOneWidget);
    });

    testWidgets('the selected chip reports its state to a screen reader', (
      tester,
    ) async {
      await _pumpAllRequests(tester);
      await _pumpAsyncContent(tester);

      // FilterChip supplies the role and selected state; this asserts the chip
      // is genuinely wired rather than painted selected.
      expect(
        tester.getSemantics(find.text('All')),
        containsSemantics(hasSelectedState: true, isSelected: true),
      );

      await tester.tap(find.text('Declined'));
      await _settle(tester);

      expect(
        tester.getSemantics(find.text('Declined')),
        containsSemantics(hasSelectedState: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.text('All')),
        containsSemantics(hasSelectedState: true, isSelected: false),
      );
    });
  });

  group('delete request', () {
    testWidgets('confirming deletes it and reports the outcome', (
      tester,
    ) async {
      final seerr = _RecordingSeerrService();
      await _pumpAllRequests(tester, seerr: seerr);
      await _pumpAsyncContent(tester);

      // The tooltip names the request, since there is one button per row.
      await tester.tap(find.byTooltip('Delete request for A Quiet Place'));
      await _settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete request'));
      await _settle(tester);

      expect(seerr.deletedIds, [1]);
      // Without feedback the row just vanishes, which reads as a glitch. The
      // SnackBar is also what announces the result, via its liveRegion.
      expect(
        find.text('Deleted the request for A Quiet Place'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final seerr = _RecordingSeerrService();
      await _pumpAllRequests(tester, seerr: seerr);
      await _pumpAsyncContent(tester);

      await tester.tap(find.byTooltip('Delete request for A Quiet Place'));
      await _settle(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester);

      expect(seerr.deletedIds, isEmpty);
    });

    testWidgets('a failure surfaces instead of failing silently', (
      tester,
    ) async {
      final seerr = _RecordingSeerrService(failure: 'HTTP 403');
      await _pumpAllRequests(tester, seerr: seerr);
      await _pumpAsyncContent(tester);

      await tester.tap(find.byTooltip('Delete request for A Quiet Place'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete request'));
      await _settle(tester);

      // Both registers, in one node: the sentence the user acts on, and the
      // diagnostic the server actually sent, demoted to its own line by
      // `SnackBarHelper`'s `detail:` contract rather than interpolated into it.
      expect(
        find.textContaining("Couldn't delete the request."),
        findsOneWidget,
      );
      expect(find.textContaining('HTTP 403'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('a request row is one button, not seven fragments', (
      tester,
    ) async {
      await _pumpAllRequests(tester);
      await _pumpAsyncContent(tester);

      expect(
        find.semantics.byLabel('A Quiet Place'),
        containsSemantics(
          value: 'Movie, requested by sarah, Available, 2026-05-02',
          isButton: true,
          hasTapAction: true,
        ),
      );

      // The bare '·' between requester and type used to be its own node, read as
      // "middle dot"; the avatar initials duplicated the name beside them.
      expect(find.semantics.byLabel('·'), findsNothing);
      expect(find.semantics.byLabel('S'), findsNothing);
    });

    testWidgets('the delete button stays reachable inside the row', (
      tester,
    ) async {
      await _pumpAllRequests(tester);
      await _pumpAsyncContent(tester);

      // The regression guard for the nested-control shape: the row silences its
      // body but must not silence this button. getSemantics walks up past merged
      // nodes, so if the row had absorbed it we would get the row's node back —
      // and the row carries no tooltip.
      expect(
        tester.getSemantics(find.byTooltip('Delete request for A Quiet Place')),
        containsSemantics(
          tooltip: 'Delete request for A Quiet Place',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });
  });

  group('targets and ink', () {
    testWidgets(
      'the delete button is a finger target around a 28pt plate',
      (tester) async {
        await _pumpAllRequests(tester);
        await _pumpAsyncContent(tester);

        final button = find.byTooltip('Delete request for A Quiet Place');
        final hitBox = tester.getSize(
          find.ancestor(of: button, matching: find.byType(IconButton)),
        );
        expect(hitBox.width, greaterThanOrEqualTo(44));
        expect(hitBox.height, greaterThanOrEqualTo(44));

        // The plate the eye sees did not grow with it.
        final plate = tester.getSize(
          find
              .descendant(
                of: find.ancestor(
                  of: button,
                  matching: find.byType(IconButton),
                ),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(plate, const Size.square(28));
      },
      variant: TargetPlatformVariant.mobile(),
    );

    testWidgets(
      'a desktop build keeps the 28pt plate as its whole target',
      (tester) async {
        await _pumpAllRequests(tester);
        await _pumpAsyncContent(tester);

        final hitBox = tester.getSize(
          find.ancestor(
            of: find.byTooltip('Delete request for A Quiet Place'),
            matching: find.byType(IconButton),
          ),
        );
        expect(hitBox, const Size.square(28));
      },
      variant: TargetPlatformVariant.desktop(),
    );

    for (final brightness in Brightness.values) {
      testWidgets('status pills clear 4.5:1 on their own wash '
          '(${brightness.name})', (tester) async {
        final theme = brightness == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme();
        await _pumpAllRequests(tester, theme: theme);
        await _pumpAsyncContent(tester);

        final pills = find.byWidgetPredicate((widget) {
          if (widget is! Container || widget.child is! Text) return false;
          final decoration = widget.decoration;
          return decoration is BoxDecoration &&
              decoration.shape == BoxShape.rectangle &&
              decoration.borderRadius != null &&
              decoration.color != null;
        });
        expect(pills, findsNWidgets(2));

        // The card the pill sits on, which the wash is composited over.
        final card = theme.colorScheme.surfaceContainer;
        for (final pill in tester.widgetList<Container>(pills)) {
          final wash = (pill.decoration! as BoxDecoration).color!;
          final label = pill.child! as Text;
          final ink = label.style!.color!;
          final ground = Color.alphaBlend(wash, card);
          expect(
            _contrast(ink, ground),
            greaterThanOrEqualTo(4.5),
            reason: '"${label.data}": $ink on $ground',
          );
        }
      });
    }
  });
}

/// WCAG 2.1 relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

class _RecordingSeerrService extends FakeSeerrService {
  _RecordingSeerrService({this.failure});

  final String? failure;
  final List<int> deletedIds = <int>[];

  @override
  Future<void> deleteRequest(int requestId) async {
    if (failure != null) throw Exception(failure);
    deletedIds.add(requestId);
  }
}

Future<void> _pumpAllRequests(
  WidgetTester tester, {
  SeerrService? seerr,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _providerOverrides(seerr: seerr),
      child: MaterialApp(theme: theme, home: const ServiceAllRequestsScreen()),
    ),
  );
}

List<Override> _providerOverrides({SeerrService? seerr}) {
  return [
    currentSettingsProvider.overrideWith(
      (ref) => settingsWith(
        seerrUrl: 'http://seerr.local:5055',
        seerrApiKey: 'key',
        radarrUrl: 'http://radarr.local:7878',
        radarrApiKey: 'key',
        sonarrUrl: 'http://sonarr.local:8989',
        sonarrApiKey: 'key',
        lidarrUrl: 'http://lidarr.local:8686',
        lidarrApiKey: 'key',
      ),
    ),
    if (seerr != null) seerrServiceProvider.overrideWithValue(seerr),
    servicesRequestsProvider.overrideWith(
      (ref) async => const [
        SeerrRequest(
          id: 1,
          status: RequestStatus.pendingApproval,
          media: RequestMedia(
            title: 'A Quiet Place',
            tmdbId: 123,
            posterPath: '/quiet-place.jpg',
            status: SeerrMediaAvailability.available,
          ),
          createdAt: '2026-05-02T10:00:00Z',
          type: 'movie',
          requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
        ),
        SeerrRequest(
          id: 2,
          status: RequestStatus.approved,
          media: RequestMedia(
            title: 'Shogun',
            status: SeerrMediaAvailability.partiallyAvailable,
          ),
          createdAt: '2026-05-01T10:00:00Z',
          type: 'tv',
          requestedBy: RequestedBy(id: 2, displayName: 'james'),
        ),
      ],
    ),
  ];
}

Future<void> _pumpAsyncContent(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Bounded pumping instead of `pumpAndSettle`.
///
/// The rows hold a `CachedNetworkImage`, which never resolves under the test
/// binding, so `pumpAndSettle` times out. 350ms is enough to run a dialog's
/// route transition to completion.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Finder _contentCardWithImage(String imagePath) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is ContentCard && widget.imageUrl?.contains(imagePath) == true,
    skipOffstage: false,
  );
}
