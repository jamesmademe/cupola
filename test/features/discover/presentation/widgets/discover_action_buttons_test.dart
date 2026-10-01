import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_action_buttons.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

import '../../../../test_helpers/settings_scope.dart';

/// `FilledButton.icon` builds a private subclass, so an exact type finder
/// misses it.
final Finder _request = find.byWidgetPredicate(
  (widget) => widget is FilledButton,
);

void main() {
  group('DiscoverActionButtons', () {
    testWidgets('shows request plus captioned trailers and open actions', (
      tester,
    ) async {
      // Still asking Radarr: the jump stays, and asks for itself when tapped.
      await _pumpButtons(tester, hasManageableMedia: false, isInService: null);

      expect(find.text('Request'), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      // The two icon buttons used to carry no visible label at all, where the
      // library ones did.
      expect(find.text('Trailers'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      // Nothing to explain: the action is available.
      expect(find.textContaining('already'), findsNothing);
    });

    testWidgets('an available title reads Available, with a reason', (
      tester,
    ) async {
      await _pumpButtons(
        tester,
        hasManageableMedia: true,
        isInService: true,
        mediaInfo: const {'id': 1, 'status': 5},
      );

      // "Requested" is the wrong word for a title that is already on disk, and
      // a disabled button with no explanation is a dead end.
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Requested'), findsNothing);
      expect(
        find.text('Already in your library, nothing to request.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_request).onPressed, isNull);
    });

    testWidgets('a requested movie says which service has it', (tester) async {
      await _pumpButtons(
        tester,
        mediaType: 'movie',
        hasManageableMedia: true,
        isInService: false,
        // Processing: Seerr sent it, and Radarr has it.
        mediaInfo: const {'id': 1, 'status': 3},
      );

      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Radarr is already tracking this.'), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('a requested series names Sonarr', (tester) async {
      await _pumpButtons(
        tester,
        mediaType: 'tv',
        hasManageableMedia: true,
        isInService: false,
        mediaInfo: const {'id': 1, 'status': 3},
      );

      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Sonarr is already tracking this.'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('a title only in service offers Open, and Request', (
      tester,
    ) async {
      await _pumpButtons(
        tester,
        mediaType: 'movie',
        hasManageableMedia: false,
        isInService: true,
      );

      // Seerr has no record of it, and Seerr is what would take the request.
      expect(find.text('Request'), findsOneWidget);
      expect(tester.widget<FilledButton>(_request).onPressed, isNotNull);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    group('Request follows what Seerr would take', () {
      // Any media row used to read as "Requested · Radarr is already tracking
      // this.", whatever the row said.
      for (final MapEntry(key: name, value: (mediaInfo, numbering)) in {
        'a row Seerr knows nothing on': (
          {'id': 1, 'status': 1},
          SeerrNumbering.seerr,
        ),
        'a film whose files were deleted (Seerr)': (
          {'id': 1, 'status': 7},
          SeerrNumbering.seerr,
        ),
        'a film whose files were deleted (Overseerr)': (
          {'id': 1, 'status': 6},
          SeerrNumbering.overseerr,
        ),
        'a film whose request was declined': (
          {
            'id': 1,
            'status': 1,
            'requests': [
              {'id': 9, 'status': 3, 'is4k': false},
            ],
          },
          SeerrNumbering.seerr,
        ),
        'a film with only a 4K request': (
          {
            'id': 1,
            'status': 1,
            'status4k': 2,
            'requests': [
              {'id': 9, 'status': 1, 'is4k': true},
            ],
          },
          SeerrNumbering.seerr,
        ),
      }.entries) {
        testWidgets('$name can be requested', (tester) async {
          await _pumpButtons(
            tester,
            hasManageableMedia: true,
            // A stack whose Radarr is known only through Seerr.
            isInService: null,
            configured: const [ServiceKey.seerr],
            mediaInfo: mediaInfo,
            numbering: numbering,
          );

          expect(find.text('Request'), findsOneWidget);
          expect(tester.widget<FilledButton>(_request).onPressed, isNotNull);
          expect(find.textContaining('already tracking'), findsNothing);
          // Manage stays: the row is still Seerr's to manage.
          expect(find.text('Manage'), findsOneWidget);
        });
      }

      testWidgets('a partly available series can request the rest, and says '
          'which seasons that is', (tester) async {
        await _pumpButtons(
          tester,
          mediaType: 'tv',
          hasManageableMedia: true,
          isInService: true,
          mediaInfo: const {
            'id': 1,
            'status': 4,
            'seasons': [
              {'seasonNumber': 1, 'status': 5},
              {'seasonNumber': 2, 'status': 5},
            ],
          },
          seasons: [_season(1), _season(2), _season(3), _season(4)],
        );

        expect(find.text('Request'), findsOneWidget);
        expect(tester.widget<FilledButton>(_request).onPressed, isNotNull);
        expect(
          find.text('Seasons 3 and 4 are not requested yet.'),
          findsOneWidget,
        );
      });

      testWidgets('a film the operator blocklisted in Seerr says so, '
          'and offers no Request', (tester) async {
        await _pumpButtons(
          tester,
          hasManageableMedia: true,
          isInService: null,
          configured: const [ServiceKey.seerr],
          mediaInfo: const {'id': 1, 'status': 6},
          numbering: SeerrNumbering.seerr,
        );

        expect(find.text('Blocklisted'), findsOneWidget);
        expect(find.text('Request'), findsNothing);
        expect(
          find.text('Blocklisted in Seerr, which takes no request for it.'),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(_request).onPressed, isNull);
      });

      testWidgets('a film waiting for approval says so', (tester) async {
        await _pumpButtons(
          tester,
          hasManageableMedia: true,
          isInService: false,
          mediaInfo: const {
            'id': 1,
            'status': 2,
            'requests': [
              {'id': 9, 'status': 1, 'is4k': false},
            ],
          },
        );

        expect(find.text('Requested'), findsOneWidget);
        expect(find.text('Waiting for approval in Seerr.'), findsOneWidget);
        expect(tester.widget<FilledButton>(_request).onPressed, isNull);
      });

      testWidgets('a film whose request failed says Seerr could not send it', (
        tester,
      ) async {
        await _pumpButtons(
          tester,
          hasManageableMedia: true,
          isInService: false,
          mediaInfo: const {
            'id': 1,
            'status': 1,
            'requests': [
              {'id': 9, 'status': 4, 'is4k': false},
            ],
          },
        );

        expect(find.text('Request failed'), findsOneWidget);
        expect(
          find.text('Seerr could not send the last request to Radarr.'),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(_request).onPressed, isNull);
      });
    });

    testWidgets('a title with nothing to play offers no Trailers', (
      tester,
    ) async {
      await _pumpButtons(
        tester,
        hasManageableMedia: false,
        isInService: true,
        videos: const [],
      );

      // It was a disabled disc, which a screen reader skips.
      expect(find.text('Trailers'), findsNothing);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(
        tester
            .widgetList<OutlinedButton>(find.byType(OutlinedButton))
            .every((button) => button.onPressed != null),
        isTrue,
      );
    });

    testWidgets('a title Radarr says it does not hold offers no Open', (
      tester,
    ) async {
      await _pumpButtons(tester, hasManageableMedia: false, isInService: false);

      // The jump could only report that it found nothing.
      expect(find.text('Open'), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
      expect(find.text('Trailers'), findsOneWidget);
    });

    testWidgets('a series Seerr sent without a TVDB id offers no Open', (
      tester,
    ) async {
      await _pumpButtons(
        tester,
        mediaType: 'tv',
        hasManageableMedia: false,
        isInService: null,
        tvdbId: null,
      );

      expect(find.text('Open'), findsNothing);
    });

    testWidgets('with no Radarr set up, Open in Radarr is dimmed but tappable '
        'and its toast leads to the setup', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpButtons(
        tester,
        hasManageableMedia: false,
        // What the page passes when Radarr is not set up: nobody could say.
        isInService: null,
        configured: const [ServiceKey.seerr],
      );

      final open = find.ancestor(
        of: find.byIcon(Icons.open_in_new_rounded),
        matching: find.byType(OutlinedButton),
      );
      expect(open, findsOneWidget);
      // Never `onPressed: null`: that is the node a screen reader skips.
      expect(tester.widget<OutlinedButton>(open).onPressed, isNotNull);
      // The glyph and its caption drain; the button's plate does not.
      for (final content in [
        find.byIcon(Icons.open_in_new_rounded),
        find.text('Open'),
      ]) {
        final dim = tester.widget<Opacity>(
          find.ancestor(of: content, matching: find.byType(Opacity)).first,
        );
        expect(dim.opacity, 0.38);
      }
      expect(
        find.ancestor(of: open, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        tester.getSemantics(open),
        containsSemantics(
          label: 'Open in Radarr',
          hint: 'requires Radarr',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(open).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(open).height, greaterThanOrEqualTo(44));

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.text('Set up Radarr to open this movie'), findsOneWidget);
      expect(
        find.widgetWithText(SnackBarAction, 'Set up Radarr'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the request action is the ink button, not Seerr\'s colour', (
      tester,
    ) async {
      // The brand book: the page's one primary is ink. It used to be filled with Seerr's
      // accent, so the request was the one control the service coloured.
      await _pumpButtons(tester, hasManageableMedia: false, isInService: false);

      final button = tester.widget<FilledButton>(_request);
      final resolved = button.style!.backgroundColor!.resolve(<WidgetState>{});
      final scheme = Theme.of(tester.element(_request)).colorScheme;
      expect(resolved, scheme.primary);
      expect(resolved, isNot(ServiceKey.seerr.brandAccent));
      expect(
        button.style!.foregroundColor!.resolve(<WidgetState>{}),
        scheme.onPrimary,
      );
    });

    testWidgets('every control clears the 44pt touch minimum', (tester) async {
      await _pumpButtons(tester, hasManageableMedia: false, isInService: true);

      expect(
        tester.getSize(_request).height,
        greaterThanOrEqualTo(HeaderActionRow.buttonHeight),
      );

      final icons = find.byType(OutlinedButton);
      expect(icons, findsNWidgets(2));
      final first = tester.getRect(icons.at(0));
      final second = tester.getRect(icons.at(1));
      for (final rect in [first, second]) {
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
      }
      expect(second.left - first.right, greaterThanOrEqualTo(8));
    });

    testWidgets('the row survives an accessibility reading size', (
      tester,
    ) async {
      await _pumpButtons(
        tester,
        hasManageableMedia: false,
        isInService: false,
        textScale: 2.0,
      );

      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Trailers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the deck never pads itself', (tester) async {
      await _pumpButtons(tester, hasManageableMedia: false, isInService: false);

      // The detail spine wraps `deck` in the resolved gutter and the gap above
      // it. This widget used to add `symmetric(horizontal: lg, vertical: md)` on
      // top, which put the Discover action row 32pt in and 12pt lower than every
      // other page's deck. Same assertion `LibraryDetailActions` carries.
      final deck = tester.getRect(find.byType(DiscoverActionButtons));
      final row = tester.getRect(find.byType(Row).first);
      expect(row.left, deck.left);
      expect(row.right, deck.right);
      expect(row.top, deck.top);
    });
  });
}

Future<void> _pumpButtons(
  WidgetTester tester, {
  String mediaType = 'movie',
  required bool hasManageableMedia,
  required bool? isInService,
  int? tvdbId = 456,
  List<TvSeason> seasons = const [],
  List<RelatedVideo> videos = const [_trailer],
  Map<String, dynamic>? mediaInfo,
  double textScale = 1.0,
  List<ServiceKey> configured = const [ServiceKey.radarr, ServiceKey.sonarr],
  SeerrNumbering numbering = SeerrNumbering.seerr,
}) async {
  // The Open jump is a cross-service control and reads whether its arr is set
  // up; both are by default, as they are wherever this row can offer Open.
  final overrides = await settingsScopeOverrides(configured: configured);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: DiscoverActionButtons(
            mediaId: 123,
            mediaType: mediaType,
            hasManageableMedia: hasManageableMedia,
            isInService: isInService,
            requestGate: seerrRequestGate(
              mediaInfo,
              isMovie: mediaType == 'movie',
              seasons: seasons,
              numbering: numbering,
            ),
            tvdbId: mediaType == 'tv' ? tvdbId : null,
            mediaInfo: mediaInfo,
            title: 'Title',
            voteAverage: 7.5,
            videos: videos,
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

TvSeason _season(int number) => TvSeason(
  id: number,
  seasonNumber: number,
  name: 'Season $number',
  episodeCount: 8,
);

const _trailer = RelatedVideo(
  url: 'https://www.youtube.com/watch?v=trailer',
  key: 'trailer',
  name: 'Official Trailer',
  type: 'Trailer',
  site: 'YouTube',
);
