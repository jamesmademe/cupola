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
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.arrived,
        HomeModule.downloads,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.setUpNext,
      ]);
      expect(HomeModule.of(requester), [
        HomeModule.trending,
        HomeModule.comingSoon,
      ]);
    });

    test('Needs you can be neither moved nor hidden; Set up next can be '
        'hidden but not moved', () {
      expect(HomeModule.needsYou.hideable, isFalse);
      expect(HomeModule.needsYou.movable, isFalse);
      expect(HomeModule.setUpNext.hideable, isTrue);
      expect(HomeModule.setUpNext.movable, isFalse);
      expect(HomeModule.orderedOf(operator), [
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.arrived,
        HomeModule.downloads,
        HomeModule.requests,
        HomeModule.nowPlaying,
      ]);
    });

    test('a stored name finds its module, an unknown one finds none', () {
      expect(HomeModule.byName('downloads'), HomeModule.downloads);
      expect(HomeModule.byName('featured'), isNull);
    });
  });

  group('reading', () {
    test('nothing stored is the default, with every module on', () {
      final layout = HomeLayout.read(null, operator);
      expect(layout.isDefault, isTrue);
      expect(layout.shown, HomeModule.of(operator));
      expect(layout.rows, HomeModule.of(operator));
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
          ['requests', 'featured', 'trending', 'downloads', 'arrived'],
          hidden: ['storage', 'comingSoon'],
        ),
        operator,
      );
      expect(layout.order, [
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.downloads,
        HomeModule.arrived,
      ]);
      expect(layout.hidden, isEmpty);
    });

    test('a module the layout does not know enters at its default place', () {
      // Written before Continue watching, Coming up, Downloads and Now
      // playing existed: each lands after the module that precedes it by
      // default, wherever the person moved that one to.
      final layout = HomeLayout.read(stored(['requests', 'arrived']), operator);
      expect(layout.order, [
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.arrived,
        HomeModule.downloads,
      ]);
      expect(layout.isOn(HomeModule.downloads), isTrue);
    });

    test('a new first module enters first', () {
      final layout = HomeLayout.read(
        stored(['requests', 'downloads']),
        operator,
      );
      expect(layout.order.first, HomeModule.continueWatching);
    });

    test('Needs you stands first and Set up next last, whatever the file '
        'says', () {
      final layout = HomeLayout.read(
        stored(
          ['setUpNext', 'requests', 'needsYou', 'downloads', 'arrived'],
          hidden: ['needsYou'],
        ),
        operator,
      );
      expect(layout.order, [
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.requests,
        HomeModule.nowPlaying,
        HomeModule.downloads,
        HomeModule.arrived,
      ]);
      expect(layout.rows.first, HomeModule.needsYou);
      expect(layout.rows.last, HomeModule.setUpNext);
      expect(layout.isOn(HomeModule.needsYou), isTrue);
    });

    test('a name stored twice counts once', () {
      final layout = HomeLayout.read(
        stored(['downloads', 'downloads', 'arrived', 'requests']),
        operator,
      );
      expect(layout.order, [
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.downloads,
        HomeModule.arrived,
        HomeModule.requests,
        HomeModule.nowPlaying,
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
      expect(layout.moved(HomeModule.continueWatching, -1), same(layout));
      expect(layout.moved(HomeModule.nowPlaying, 5), same(layout));
      expect(layout.moved(HomeModule.arrived, 1).order, [
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.downloads,
        HomeModule.arrived,
        HomeModule.requests,
        HomeModule.nowPlaying,
      ]);
      expect(
        layout.moved(HomeModule.requests, -9).order.first,
        HomeModule.requests,
      );
    });

    test('a module that is not ordered does not move', () {
      expect(layout.moved(HomeModule.needsYou, 1), same(layout));
      expect(layout.moved(HomeModule.setUpNext, -1), same(layout));
    });

    test('a drag counts the dragged module\'s own slot, as a reorderable '
        'list reports it', () {
      // Arrived dropped below Requests: the list reports index 5.
      expect(layout.reordered(2, 5).order, [
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.downloads,
        HomeModule.requests,
        HomeModule.arrived,
        HomeModule.nowPlaying,
      ]);
      // Requests dropped on top.
      expect(layout.reordered(4, 0).order, [
        HomeModule.requests,
        HomeModule.continueWatching,
        HomeModule.comingUp,
        HomeModule.arrived,
        HomeModule.downloads,
        HomeModule.nowPlaying,
      ]);
      expect(layout.reordered(1, 2), same(layout));
      expect(layout.reordered(9, 0), same(layout));
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
      expect(layout.summary, '8 modules');
      expect(
        layout.switched(HomeModule.requests, on: false).summary,
        '8 modules · Requests hidden',
      );
      expect(
        layout
            .switched(HomeModule.requests, on: false)
            .switched(HomeModule.setUpNext, on: false)
            .summary,
        '8 modules · 2 hidden',
      );
      expect(HomeLayout.defaultFor(requester).summary, '2 modules');
    });
  });
}
