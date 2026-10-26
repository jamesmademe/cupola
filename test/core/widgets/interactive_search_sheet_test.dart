import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/interactive_search_sheet.dart';

void main() {
  group('InteractiveSearchSheet filtering', () {
    testWidgets('summarises the result counts', (tester) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      expect(find.text('3 releases\u00A0· 2 approved'), findsOneWidget);
    });

    testWidgets('filters by title query', (tester) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      await tester.enterText(find.byType(TextField), 'remux');
      await tester.pumpAndSettle();

      expect(find.text('Movie.2024.2160p.REMUX'), findsOneWidget);
      expect(find.text('Movie.2024.1080p.WEB-DL'), findsNothing);
      expect(find.text('1 of 3 releases\u00A0· 2 approved'), findsOneWidget);
    });

    testWidgets('hides rejected releases behind the Approved only chip', (
      tester,
    ) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      await tester.tap(find.text('Approved only'));
      await tester.pumpAndSettle();

      expect(find.text('Movie.2024.720p.Rejected'), findsNothing);
      expect(find.text('2 of 3 releases\u00A0· 2 approved'), findsOneWidget);
    });

    testWidgets('offers a way back when filters exclude everything', (
      tester,
    ) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      await tester.enterText(find.byType(TextField), 'nothing matches this');
      await tester.pumpAndSettle();

      expect(find.text('No releases match filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('3 releases\u00A0· 2 approved'), findsOneWidget);
    });

    testWidgets('shows an empty state when no release was returned', (
      tester,
    ) async {
      await _pumpSheet(tester, releases: const []);

      expect(find.text('No releases found'), findsOneWidget);
    });

    testWidgets('every empty branch scrolls with the sheet controller', (
      tester,
    ) async {
      // A `Center` here detaches the controller `AppBottomSheet.showScrollable`
      // handed in, and drag-to-resize and flick-to-close stop working the moment
      // a filter empties the list.
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpSheet(
        tester,
        releases: const [],
        scrollController: controller,
      );
      expect(
        _listViewAround(tester, 'No releases found').controller,
        controller,
      );

      await _pumpSheet(
        tester,
        releases: _sampleReleases,
        scrollController: controller,
      );
      await tester.enterText(find.byType(TextField), 'nothing matches this');
      await tester.pumpAndSettle();

      expect(
        _listViewAround(tester, 'No releases match filters').controller,
        controller,
      );
    });
  });

  group('InteractiveSearchSheet grabbing', () {
    testWidgets('a grab closes the sheet and reports the download', (
      tester,
    ) async {
      final grabbed = <String>[];
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (guid, _) async => grabbed.add(guid),
      );

      await _grabFirstRelease(tester);

      expect(grabbed, hasLength(1));
      expect(find.text('Download started'), findsOneWidget);
      expect(find.byType(InteractiveSearchSheet), findsNothing);
    });

    testWidgets('an abandoned grab leaves the sheet open and silent', (
      tester,
    ) async {
      // The release-search sheet's expired-list prompt returns without grabbing
      // when it is cancelled. Reported as a normal return, that closed the sheet
      // under a green "Download started" for a download nobody started.
      var attempts = 0;
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (_, _) async {
          attempts++;
          throw const ReleaseGrabAbandoned();
        },
      );

      await _grabFirstRelease(tester);

      expect(attempts, 1);
      expect(find.byType(InteractiveSearchSheet), findsOneWidget);
      expect(find.text('Download started'), findsNothing);
      // Not a failure either: the caller has already said why.
      expect(find.byType(SnackBar), findsNothing);

      // And the list is re-armed rather than dead for the life of the sheet.
      expect(find.byTooltip('Another download is starting'), findsNothing);
      await _grabFirstRelease(tester);
      expect(attempts, 2);
    });

    testWidgets('a grab that outlives its row still closes and confirms', (
      tester,
    ) async {
      final completer = Completer<void>();
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (_, _) => completer.future,
      );

      await _startGrabInFlight(tester);
      expect(find.byTooltip('Another download is starting'), findsWidgets);

      // The toolbar stays live during a grab, so a filter can empty the list
      // and take the grabbing row's element with it while the request runs on.
      await _emptyTheList(tester);

      completer.complete();
      await tester.pumpAndSettle();

      // The download *did* start. Reporting through the row's dead element
      // skipped the pop and the confirmation and quietly re-armed every button
      // instead. Nothing on screen said anything had happened, and tapping the
      // same release again grabbed it twice.
      expect(find.byType(InteractiveSearchSheet), findsNothing);
      expect(find.text('Download started'), findsOneWidget);
    });

    testWidgets('a failed grab that outlives its row still re-arms the sheet', (
      tester,
    ) async {
      // The other half: a failure keeps the sheet open, so the busy state has
      // to clear and the reason has to be shown, and neither can depend on the
      // row that started it still being in the tree.
      final completer = Completer<void>();
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (_, _) => completer.future,
      );

      await _startGrabInFlight(tester);
      await _emptyTheList(tester);

      completer.completeError(Exception('indexer said no'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);

      // The filter row's Clear is a full 48dp target now, which moves the
      // empty state under it to the edge of the 600pt test window.
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveSearchSheet), findsOneWidget);
      expect(find.byTooltip('Another download is starting'), findsNothing);
      expect(find.byTooltip('Grab release'), findsNWidgets(3));
    });
  });
}

/// Confirms a grab and leaves it in flight.
///
/// Deliberately no `pumpAndSettle` after the confirmation: the grabbing row
/// spins on an indeterminate indicator, so nothing ever settles while the
/// request is outstanding.
Future<void> _startGrabInFlight(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Grab release').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Download release'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Filters the list down to nothing, which deactivates the grabbing row.
Future<void> _emptyTheList(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'nothing matches this');
  await tester.pumpAndSettle();
  expect(find.text('No releases match filters'), findsOneWidget);
}

/// The nearest [ListView] above [text], which is what proves an empty branch is
/// a scrollable rather than a `Center`.
ListView _listViewAround(WidgetTester tester, String text) =>
    tester.widget<ListView>(
      find.ancestor(of: find.text(text), matching: find.byType(ListView)).first,
    );

Future<void> _grabFirstRelease(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Grab release').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Download release'));
  await tester.pumpAndSettle();
}

final _sampleReleases = [
  _release(title: 'Movie.2024.1080p.WEB-DL', protocol: 'usenet'),
  _release(title: 'Movie.2024.2160p.REMUX', protocol: 'torrent', seeders: 20),
  _release(
    title: 'Movie.2024.720p.Rejected',
    protocol: 'usenet',
    rejections: const ['Quality below cutoff'],
  ),
];

Map<String, dynamic> _release({
  required String title,
  String indexer = 'NZBgeek',
  String protocol = 'usenet',
  int seeders = 0,
  List<dynamic> rejections = const [],
}) {
  return {
    'guid': title,
    'indexerId': 1,
    'title': title,
    'indexer': indexer,
    'protocol': protocol,
    'seeders': seeders,
    'size': 1073741824,
    'ageMinutes': 60,
    'quality': {
      'quality': {'name': '1080p'},
    },
    'customFormatScore': 0,
    'customFormats': const [],
    'rejections': rejections,
    'approved': rejections.isEmpty,
  };
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required List<dynamic> releases,
  ScrollController? scrollController,
}) async {
  final controller = scrollController ?? ScrollController();
  if (scrollController == null) {
    addTearDown(controller.dispose);
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InteractiveSearchSheet(
          releases: releases,
          title: 'Releases',
          onGrabRelease: (_, _) async {},
          scrollController: controller,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the sheet on a real modal route, which is what a grab needs: it pops
/// the route it is on and reports through the messenger above it.
Future<void> _showSheet(
  WidgetTester tester, {
  required List<dynamic> releases,
  required Future<void> Function(String guid, int indexerId) onGrabRelease,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _InteractiveSearchSheetLauncher(
        releases: releases,
        onGrabRelease: onGrabRelease,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _InteractiveSearchSheetLauncher extends StatefulWidget {
  const _InteractiveSearchSheetLauncher({
    required this.releases,
    this.onGrabRelease,
  });

  /// The resolved list the sheet opens on.
  final List<dynamic> releases;

  final Future<void> Function(String guid, int indexerId)? onGrabRelease;

  @override
  State<_InteractiveSearchSheetLauncher> createState() =>
      _InteractiveSearchSheetLauncherState();
}

class _InteractiveSearchSheetLauncherState
    extends State<_InteractiveSearchSheetLauncher> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final releases = widget.releases;
      final onGrabRelease = widget.onGrabRelease ?? (String _, int _) async {};

      AppBottomSheet.showScrollable(
        context: context,
        title: 'Releases',
        subtitle: 'Interactive Search',
        icon: Icons.travel_explore_rounded,
        showClose: true,
        initialSize: 0.75,
        minSize: 0.5,
        maxSize: 0.95,
        builder: (context, scrollController) => InteractiveSearchSheet(
          releases: releases,
          title: 'Interactive Search',
          onGrabRelease: onGrabRelease,
          scrollController: scrollController,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('LauncherPage')));
  }
}
