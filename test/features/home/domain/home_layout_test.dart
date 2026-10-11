import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';

/// The Home's saved layout: read against the registry every time, never
/// trusted as it was written.
void main() {
  const operator = Audience.operator;
  const requester = Audience.requester;

  String stored(List<String> order, {List<String> hidden = const []}) =>
      jsonEncode({'v': HomeLayout.version, 'order': order, 'hidden': hidden});

  group('the registry', () {
    test('each person has their own modules, in the default order', () {
      expect(HomeModule.of(operator), [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.arrived,
        HomeModule.downloads,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
        HomeModule.setUpNext,
      ]);
      expect(HomeModule.of(requester), [
        HomeModule.readyToWatch,
        HomeModule.yourRequests,
        HomeModule.trending,
        HomeModule.comingSoon,
      ]);
    });

    test('Needs you can be moved but never hidden; Set up next can be hidden '
        'but not moved', () {
      expect(HomeModule.needsYou.hideable, isFalse);
      expect(HomeModule.needsYou.movable, isTrue);
      expect(HomeModule.setUpNext.hideable, isTrue);
      expect(HomeModule.setUpNext.movable, isFalse);
      expect(HomeModule.orderedOf(operator), [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.arrived,
        HomeModule.downloads,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
      ]);
    });

    test('a stored name finds its module, an unknown one finds none', () {
      expect(HomeModule.byName('downloads'), HomeModule.downloads);
      expect(HomeModule.byName('mediaLibrary'), isNull);
    });
  });

  group('reading', () {
    test('nothing stored is the default, every module on but the three a '
        'person adds', () {
      final layout = HomeLayout.read(null, operator);
      expect(layout.isDefault, isTrue);
      expect(layout.rows, HomeModule.of(operator));
      expect(layout.hidden, {
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
      });
      expect(layout.shown, [
        for (final module in HomeModule.of(operator))
          if (module.defaultOn) module,
      ]);
    });

    test('a damaged value or another version is the default', () {
      for (final value in [
        '',
        'not json',
        '[]',
        jsonEncode({
          'v': 2,
          'order': ['requests'],
          'hidden': [],
        }),
        jsonEncode({
          'order': ['requests'],
        }),
      ]) {
        expect(
          HomeLayout.read(value, operator).isDefault,
          isTrue,
          reason: value,
        );
      }
    });

    test('a name no module has drops, and so does another person\'s', () {
      final layout = HomeLayout.read(
        stored(
          ['requests', 'mediaLibrary', 'trending', 'downloads', 'arrived'],
          hidden: ['diskSpace', 'comingSoon'],
        ),
        operator,
      );
      expect(layout.order, [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
        HomeModule.downloads,
        HomeModule.arrived,
      ]);
      // The modules it did not know enter as the registry starts them.
      expect(layout.hidden, {
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
      });
    });

    test('a module the layout does not know enters at its default place', () {
      // Written before Featured, Continue watching, Coming up, Downloads and
      // Now playing existed: each lands after the module that precedes it by
      // default, wherever the person moved that one to.
      final layout = HomeLayout.read(stored(['requests', 'arrived']), operator);
      expect(layout.order, [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
        HomeModule.arrived,
        HomeModule.downloads,
      ]);
      expect(layout.isOn(HomeModule.downloads), isTrue);
      // On or off as the registry starts it.
      expect(layout.isOn(HomeModule.storage), isFalse);
    });

    test('a module the person switched on stays on when read back', () {
      final on = HomeLayout.defaultFor(
        operator,
      ).switched(HomeModule.storage, on: true);
      final read = HomeLayout.read(on.toJson(), operator);
      expect(read.isOn(HomeModule.storage), isTrue);
      expect(read.isOn(HomeModule.stackHealth), isFalse);
    });

    test('a layout written before Needs you existed starts with it', () {
      // The first build wrote no Needs you into the order: it enters at the
      // top, where the registry puts it by default.
      final layout = HomeLayout.read(
        stored(['requests', 'downloads']),
        operator,
      );
      expect(layout.order.first, HomeModule.needsYou);
      expect(layout.rows.first, HomeModule.needsYou);
    });

    test('Set up next stays last whatever the file says, and Needs you is '
        'never hidden', () {
      final layout = HomeLayout.read(
        stored(
          ['setUpNext', 'requests', 'downloads', 'arrived'],
          hidden: ['needsYou'],
        ),
        operator,
      );
      expect(layout.rows.last, HomeModule.setUpNext);
      expect(layout.order, isNot(contains(HomeModule.setUpNext)));
      expect(layout.rows.first, HomeModule.needsYou);
      expect(layout.isOn(HomeModule.needsYou), isTrue);
    });

    test('a name stored twice counts once', () {
      final layout = HomeLayout.read(
        stored(['downloads', 'downloads', 'arrived', 'requests']),
        operator,
      );
      expect(layout.order, [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.downloads,
        HomeModule.arrived,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
      ]);
    });

    test('what is written reads back the same', () {
      final written = HomeLayout.defaultFor(operator)
          .moved(HomeModule.requests, -2)
          .switched(HomeModule.downloads, on: false)
          .switched(HomeModule.setUpNext, on: false);
      final read = HomeLayout.read(written.toJson(), operator);
      expect(read.order, written.order);
      expect(read.hidden, written.hidden);
      expect(read.shown, [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.requests,
        HomeModule.arrived,
        HomeModule.nowPlaying,
      ]);
    });

    test('the two people keep their layouts apart', () {
      expect(HomeLayout.keyFor(operator), 'home_layout_operator');
      expect(HomeLayout.keyFor(requester), 'home_layout_requester');
    });
  });

  group('arranging', () {
    final layout = HomeLayout.defaultFor(operator);

    test('a move is clamped to the ends of the order', () {
      expect(layout.moved(HomeModule.needsYou, -1), same(layout));
      expect(layout.moved(HomeModule.discoverShelf, 5), same(layout));
      expect(layout.moved(HomeModule.arrived, 1).order, [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.downloads,
        HomeModule.arrived,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
      ]);
      expect(
        layout.moved(HomeModule.requests, -9).order.first,
        HomeModule.requests,
      );
    });

    test('Needs you moves within the order; Set up next is not in it', () {
      expect(layout.moved(HomeModule.needsYou, 1).order.take(2), [
        HomeModule.featured,
        HomeModule.needsYou,
      ]);
      expect(layout.moved(HomeModule.setUpNext, -1), same(layout));
    });

    test('moved to third, Needs you is drawn third, and it reads back so', () {
      final moved = layout.moved(HomeModule.needsYou, 2);
      expect(moved.shown.take(3), [
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.needsYou,
      ]);
      final read = HomeLayout.read(moved.toJson(), operator);
      expect(read.shown.take(3), moved.shown.take(3));
    });

    test('a drag counts the dragged module\'s own slot, as a reorderable '
        'list reports it', () {
      // Arrived dropped below Requests: the list reports index 7.
      expect(layout.reordered(4, 7).order, [
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.downloads,
        HomeModule.requests,
        HomeModule.arrived,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
      ]);
      // Requests dropped on top, above Needs you: it is the person's order.
      expect(layout.reordered(6, 0).order, [
        HomeModule.requests,
        HomeModule.needsYou,
        HomeModule.featured,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.arrived,
        HomeModule.downloads,
        HomeModule.nowPlaying,
        HomeModule.stackHealth,
        HomeModule.storage,
        HomeModule.discoverShelf,
      ]);
      expect(layout.reordered(2, 3), same(layout));
      expect(layout.reordered(12, 0), same(layout));
    });

    test('Needs you cannot be switched off, nor another person\'s module '
        'on this Home', () {
      expect(layout.switched(HomeModule.needsYou, on: false), same(layout));
      expect(layout.switched(HomeModule.trending, on: false), same(layout));
    });

    test('a module switched off leaves the Home and keeps its place', () {
      final off = layout.switched(HomeModule.downloads, on: false);
      expect(off.order, layout.order);
      expect(off.shown, isNot(contains(HomeModule.downloads)));
      expect(off.isDefault, isFalse);
      expect(off.switched(HomeModule.downloads, on: true).isDefault, isTrue);
    });
  });

  group('the summary Settings prints', () {
    final layout = HomeLayout.defaultFor(operator);

    test('how many modules, and which are off', () {
      expect(layout.summary, '9 modules');
      expect(
        layout.switched(HomeModule.requests, on: false).summary,
        '8 modules · Requests hidden',
      );
      expect(
        layout
            .switched(HomeModule.requests, on: false)
            .switched(HomeModule.setUpNext, on: false)
            .summary,
        '7 modules · 2 hidden',
      );
      // A module that starts off is added, not unhidden.
      expect(
        layout.switched(HomeModule.storage, on: true).summary,
        '10 modules',
      );
      expect(HomeLayout.defaultFor(requester).summary, '4 modules');
    });
  });
}
