/// How the Home lays its modules out at a width: one column, short modules in
/// pairs, or two columns.
///
/// The phone is the product, and every module is drawn at its 390pt measure.
/// What a wider page does with them is decided here by the page's width alone,
/// never by the platform: a tablet and a desktop window of the same width get
/// the same Home.
library;

import 'package:cupola/features/home/domain/home_module.dart';

/// The three ways the Home sits on a page.
enum HomeMode {
  /// The phone's column, in the reading well on a wider page.
  single,

  /// Wide enough for two modules at the phone's measure side by side: the
  /// short ones pair up, the rest keep the whole width.
  pairs,

  /// Wide enough for two columns: what is happening on the left, what waits
  /// on the right.
  columns;

  /// The mode at [width], the page's usable width.
  static HomeMode at(double width) => width >= columnsFrom
      ? HomeMode.columns
      : width >= pairsFrom
      ? HomeMode.pairs
      : HomeMode.single;

  /// Two modules at the phone's 390pt measure.
  static const double pairsFrom = 780;

  /// A main column of at least 560 beside a side one of at least 400.
  static const double columnsFrom = 960;
}

/// Where a module goes on a page wide enough to choose.
enum HomePlace {
  /// Across the whole page, whatever the mode: the line that needs you, and
  /// the shelves of posters.
  across,

  /// The left column: what is happening, mostly pictures.
  main,

  /// The right column, and the modules that pair up: short lists of what is
  /// coming, moving, or waiting for an answer.
  side,
}

/// The place of [module].
HomePlace homePlaceOf(HomeModule module) => switch (module) {
  HomeModule.needsYou ||
  HomeModule.trending ||
  HomeModule.comingSoon ||
  HomeModule.discoverShelf => HomePlace.across,
  HomeModule.featured ||
  HomeModule.continueWatching ||
  HomeModule.arrived ||
  HomeModule.nowPlaying ||
  HomeModule.readyToWatch ||
  HomeModule.yourRequests => HomePlace.main,
  HomeModule.comingUp ||
  HomeModule.downloads ||
  HomeModule.requests ||
  HomeModule.stackHealth ||
  HomeModule.storage ||
  HomeModule.setUpNext => HomePlace.side,
};

/// One row of the Home as laid out: a module across the page, two side by
/// side, or the two columns with what each holds.
sealed class HomeRow {
  const HomeRow();
}

class HomeRowOne extends HomeRow {
  const HomeRowOne(this.module);
  final HomeModule module;

  @override
  bool operator ==(Object other) =>
      other is HomeRowOne && other.module == module;
  @override
  int get hashCode => module.hashCode;
  @override
  String toString() => 'one(${module.name})';
}

class HomeRowPair extends HomeRowOne {
  const HomeRowPair(super.module, this.second);
  final HomeModule second;

  @override
  bool operator ==(Object other) =>
      other is HomeRowPair && other.module == module && other.second == second;
  @override
  int get hashCode => Object.hash(module, second);
  @override
  String toString() => 'pair(${module.name}, ${second.name})';
}

class HomeRowColumns extends HomeRow {
  const HomeRowColumns({required this.main, required this.side});
  final List<HomeModule> main;
  final List<HomeModule> side;

  @override
  bool operator ==(Object other) =>
      other is HomeRowColumns &&
      _same(other.main, main) &&
      _same(other.side, side);
  @override
  int get hashCode => Object.hash(Object.hashAll(main), Object.hashAll(side));
  @override
  String toString() =>
      'columns(${main.map((m) => m.name)}, ${side.map((m) => m.name)})';
}

bool _same(List<HomeModule> a, List<HomeModule> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The person's modules, in their order ([shown]), laid out in [mode].
///
/// Pairs: two side modules next to each other in the person's order pair up;
/// one on its own, or any other module, keeps the whole width. Columns: what
/// goes across the page before the first column module stays above the
/// columns, what goes across after it (the shelves) below them, and each
/// column keeps the person's order.
List<HomeRow> homeRowsOf(List<HomeModule> shown, HomeMode mode) {
  switch (mode) {
    case HomeMode.single:
      return [for (final module in shown) HomeRowOne(module)];
    case HomeMode.pairs:
      final rows = <HomeRow>[];
      for (var i = 0; i < shown.length; i++) {
        final module = shown[i];
        final next = i + 1 < shown.length ? shown[i + 1] : null;
        if (homePlaceOf(module) == HomePlace.side &&
            next != null &&
            homePlaceOf(next) == HomePlace.side) {
          rows.add(HomeRowPair(module, next));
          i++;
        } else {
          rows.add(HomeRowOne(module));
        }
      }
      return rows;
    case HomeMode.columns:
      final above = <HomeRow>[];
      final below = <HomeRow>[];
      final main = <HomeModule>[];
      final side = <HomeModule>[];
      for (final module in shown) {
        switch (homePlaceOf(module)) {
          case HomePlace.across:
            (main.isEmpty && side.isEmpty ? above : below).add(
              HomeRowOne(module),
            );
          case HomePlace.main:
            main.add(module);
          case HomePlace.side:
            side.add(module);
        }
      }
      return [
        ...above,
        if (main.isNotEmpty || side.isNotEmpty)
          HomeRowColumns(main: main, side: side),
        ...below,
      ];
  }
}
