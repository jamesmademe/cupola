import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/a11y_announce.dart';

import '../../test_helpers/semantics_announcements.dart';

void main() {
  // The channel is chosen from the engine's `supportsAnnounce`, never from the
  // platform; each group pairs the flag with the platform whose engine sets it
  // that way, so the test reads as the device behaves.
  group('where the engine has no announcement channel', () {
    final android = TargetPlatformVariant.only(TargetPlatform.android);

    testWidgets(
      'the message lands on a live region, and nothing goes out natively',
      (tester) async {
        final native = SemanticsAnnouncementRecorder.install(
          tester,
          supportsAnnounce: false,
        );
        final context = await _pumpApp(tester);

        announce(context, 'Refreshing Dashboard');
        await tester.pump();

        expect(
          find.semantics.byLabel('Refreshing Dashboard'),
          isSemantics(isLiveRegion: true),
        );
        expect(native.messages, isEmpty);
      },
      variant: android,
    );

    testWidgets('the same message twice is announced twice', (tester) async {
      SemanticsAnnouncementRecorder.install(tester, supportsAnnounce: false);
      final context = await _pumpApp(tester);

      announce(context, 'Refreshing Dashboard');
      await tester.pump();
      final first = _liveRegionIds();
      expect(first, hasLength(1));

      // Android's bridge speaks a live region when its label changes, and a
      // label set to the value it holds changes nothing: the second one has to
      // be a node the bridge has not seen, whether the first is still up...
      announce(context, 'Refreshing Dashboard');
      await tester.pump();
      final both = _liveRegionIds();
      expect(both, hasLength(2));
      expect(both.first, first.single);
      expect(find.semantics.byLabel('Refreshing Dashboard'), findsExactly(2));

      // ...or long gone.
      await tester.pump(AnnouncementHost.linger);
      expect(_liveRegionIds(), isEmpty);
      announce(context, 'Refreshing Dashboard');
      await tester.pump();
      final third = _liveRegionIds();
      expect(third, hasLength(1));
      expect(both, isNot(contains(third.single)));
    }, variant: android);

    testWidgets('messages sent before a frame draws become one sentence', (
      tester,
    ) async {
      SemanticsAnnouncementRecorder.install(tester, supportsAnnounce: false);
      final context = await _pumpApp(tester);

      announce(context, 'Portal open. 2 services, none with a fault.');
      announce(context, 'Refreshing Dashboard');
      await tester.pump();

      // One node, one content-change event: nothing for TalkBack to collapse
      // or cut short, and both sentences in the order they were sent.
      expect(_liveRegionIds(), hasLength(1));
      expect(
        find.semantics.byLabel(
          'Portal open. 2 services, none with a fault.\nRefreshing Dashboard',
        ),
        isSemantics(isLiveRegion: true),
      );
    }, variant: android);

    testWidgets(
      'a message a frame later gets a node of its own, and neither relabels '
      'the other',
      (tester) async {
        SemanticsAnnouncementRecorder.install(tester, supportsAnnounce: false);
        final context = await _pumpApp(tester);

        announce(context, 'First');
        await tester.pump();
        final firstId = _idOf('First');

        await tester.pump(const Duration(seconds: 1));
        announce(context, 'Second');
        await tester.pump();

        // The first is not taken away before the reader could fetch it.
        expect(_idOf('First'), firstId);
        final secondId = _idOf('Second');

        // The first expires; the second keeps its node, so its sentence is
        // not announced again under a changed label.
        await tester.pump(AnnouncementHost.linger - const Duration(seconds: 1));
        expect(find.semantics.byLabel('First'), findsNothing);
        expect(_idOf('Second'), secondId);

        await tester.pump(const Duration(seconds: 1));
        expect(_liveRegionIds(), isEmpty);
      },
      variant: android,
    );

    testWidgets('an announcement made while a frame builds is drawn next', (
      tester,
    ) async {
      SemanticsAnnouncementRecorder.install(tester, supportsAnnounce: false);
      var announced = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AnnouncementHost(child: child!),
          home: LayoutBuilder(
            builder: (context, constraints) {
              if (!announced) {
                announced = true;
                announce(context, 'Laid out');
              }
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.semantics.byLabel('Laid out'),
        isSemantics(isLiveRegion: true),
      );
    }, variant: android);

    testWidgets('an empty message draws nothing', (tester) async {
      SemanticsAnnouncementRecorder.install(tester, supportsAnnounce: false);
      final context = await _pumpApp(tester);

      announce(context, '');
      await tester.pump();

      expect(_liveRegionIds(), isEmpty);
    }, variant: android);
  });

  group('where the engine has one', () {
    testWidgets('the message goes out natively, and no live region is drawn', (
      tester,
    ) async {
      final native = SemanticsAnnouncementRecorder.install(tester);
      final context = await _pumpApp(tester);

      announce(context, 'Refreshing Dashboard');
      await tester.pump();

      expect(native.messages, ['Refreshing Dashboard']);
      // VoiceOver would otherwise read it twice.
      expect(_liveRegionIds(), isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}

/// The app as `CupolaApp` builds it: the host around everything the router
/// draws. Returns a context under it, the way a screen calls [announce].
Future<BuildContext> _pumpApp(WidgetTester tester) async {
  late BuildContext page;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => AnnouncementHost(child: child!),
      home: Builder(
        builder: (context) {
          page = context;
          return const Scaffold(body: Text('Page'));
        },
      ),
    ),
  );
  return page;
}

/// The ids of the live-region nodes on screen, in paint order.
List<int> _liveRegionIds() {
  return find.semantics
      .byPredicate(
        (node) => node.getSemanticsData().flagsCollection.isLiveRegion,
      )
      .evaluate()
      .map((SemanticsNode node) => node.id)
      .toList();
}

/// The id of the one node labelled [label]: the identity Android's bridge
/// keys a live region's label change on.
int _idOf(String label) => find.semantics.byLabel(label).evaluate().single.id;
