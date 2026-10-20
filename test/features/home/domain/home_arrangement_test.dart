import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/home_arrangement.dart';
import 'package:cupola/features/home/domain/home_module.dart';

/// How the Home sits on a page: decided by the page's width alone.
void main() {
  const operator = [
    HomeModule.needsYou,
    HomeModule.featured,
    HomeModule.comingUp,
    HomeModule.arrived,
    HomeModule.downloads,
    HomeModule.requests,
    HomeModule.nowPlaying,
    HomeModule.stackHealth,
    HomeModule.trending,
  ];

  test('the mode follows the width, whatever the platform', () {
    expect(HomeMode.at(390), HomeMode.single);
    expect(HomeMode.at(779), HomeMode.single);
    expect(HomeMode.at(780), HomeMode.pairs);
    expect(HomeMode.at(959), HomeMode.pairs);
    expect(HomeMode.at(960), HomeMode.columns);
    expect(HomeMode.at(1140), HomeMode.columns);
  });

  test('one column keeps the person\'s order, one module a row', () {
    expect(homeRowsOf(operator, HomeMode.single), [
      for (final module in operator) HomeRowOne(module),
    ]);
  });

  test('in pairs, two short modules next to each other share a row; the '
      'rest keep the width', () {
    expect(homeRowsOf(operator, HomeMode.pairs), const [
      HomeRowOne(HomeModule.needsYou),
      HomeRowOne(HomeModule.featured),
      HomeRowOne(HomeModule.comingUp),
      HomeRowOne(HomeModule.arrived),
      HomeRowPair(HomeModule.downloads, HomeModule.requests),
      HomeRowOne(HomeModule.nowPlaying),
      HomeRowOne(HomeModule.stackHealth),
      HomeRowOne(HomeModule.trending),
    ]);
  });

  test('in columns, what happens left and what waits right, each in the '
      'person\'s order; the line above, the shelves below', () {
    expect(homeRowsOf(operator, HomeMode.columns), const [
      HomeRowOne(HomeModule.needsYou),
      HomeRowColumns(
        main: [HomeModule.featured, HomeModule.arrived, HomeModule.nowPlaying],
        side: [
          HomeModule.comingUp,
          HomeModule.downloads,
          HomeModule.requests,
          HomeModule.stackHealth,
        ],
      ),
      HomeRowOne(HomeModule.trending),
    ]);
  });

  test('a Home of shelves alone draws no empty columns', () {
    expect(homeRowsOf(const [HomeModule.trending], HomeMode.columns), const [
      HomeRowOne(HomeModule.trending),
    ]);
  });

  test('every module has a place', () {
    for (final module in HomeModule.values) {
      expect(homePlaceOf(module), isA<HomePlace>(), reason: module.name);
    }
  });
}
