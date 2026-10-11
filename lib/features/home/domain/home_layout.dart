/// How one person arranged their Home: the order of its modules and the ones
/// switched off.
///
/// Kept on the device, one per person (`home_layout_operator`,
/// `home_layout_requester`), as a small versioned JSON object. It is read
/// against the registry ([HomeModule]) every time, never trusted as it was
/// written:
///
///  * a name no module has any more is dropped;
///  * a module the layout does not know yet enters at its default place, on
///    or off as the registry starts it;
///  * Set up next stands last whatever the file says. Needs you is first by
///    default and may be moved, but it is never hidden.
///
/// A file this build cannot read (another version, a damaged value) is the
/// default layout: arranging the Home again costs a minute, a Home that does
/// not open costs the app.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/home/domain/home_module.dart';

@immutable
class HomeLayout {
  const HomeLayout._({
    required this.audience,
    required this.order,
    required this.hidden,
  });

  /// [audience]'s Home as the registry starts it.
  factory HomeLayout.defaultFor(Audience audience) => HomeLayout._(
    audience: audience,
    order: HomeModule.orderedOf(audience),
    hidden: {
      for (final module in HomeModule.of(audience))
        if (module.hideable && !module.defaultOn) module,
    },
  );

  /// The layout [stored] describes for [audience], read by the rules in the
  /// library's doc. Null or unreadable is the default.
  factory HomeLayout.read(String? stored, Audience audience) {
    if (stored == null || stored.isEmpty) {
      return HomeLayout.defaultFor(audience);
    }
    try {
      final json = jsonDecode(stored);
      if (json is! Map<String, Object?> || json['v'] != version) {
        return HomeLayout.defaultFor(audience);
      }
      final order = _modules(json['order'], audience);
      final hidden = _modules(json['hidden'], audience).toSet();
      return _completed(audience, order, hidden);
    } on FormatException {
      return HomeLayout.defaultFor(audience);
    }
  }

  /// The version this build writes and reads.
  static const version = 1;

  /// The preference that keeps [audience]'s layout.
  static String keyFor(Audience audience) => switch (audience) {
    Audience.operator => 'home_layout_operator',
    Audience.requester => 'home_layout_requester',
  };

  /// Whose Home this is.
  final Audience audience;

  /// The modules the person orders, every one of them, on or off.
  final List<HomeModule> order;

  /// The modules switched off.
  final Set<HomeModule> hidden;

  /// What Edit Home lists: the ordered modules, then the one pinned at the foot.
  List<HomeModule> get rows => [
    ...order,
    for (final module in HomeModule.of(audience))
      if (module.placement == HomePlacement.last) module,
  ];

  /// What the Home draws, in order, before each module decides whether it
  /// has anything to say.
  List<HomeModule> get shown => [
    for (final module in rows)
      if (isOn(module)) module,
  ];

  bool isOn(HomeModule module) => !hidden.contains(module);

  /// Whether this is the layout the registry starts with: Reset to default has
  /// nothing to do.
  bool get isDefault {
    final fresh = HomeLayout.defaultFor(audience);
    return listEquals(order, fresh.order) && setEquals(hidden, fresh.hidden);
  }

  /// What Settings says of it: how many modules the Home draws, and which
  /// the person switched off: `9 modules`, `8 modules · Requests hidden`,
  /// `7 modules · 2 hidden`. A module that starts off is not hidden: it waits
  /// in Edit Home to be added, and once on it counts.
  String get summary {
    final on = shown.length;
    final count = '$on ${on == 1 ? 'module' : 'modules'}';
    final off = [
      for (final module in rows)
        if (!isOn(module) && module.defaultOn) module,
    ];
    return switch (off.length) {
      0 => count,
      1 => '$count · ${off.single.label} hidden',
      _ => '$count · ${off.length} hidden',
    };
  }

  /// [module] moved [by] places in the order, clamped to its ends.
  HomeLayout moved(HomeModule module, int by) {
    final from = order.indexOf(module);
    if (from < 0) return this;
    final to = (from + by).clamp(0, order.length - 1);
    if (to == from) return this;
    return _withOrder(
      [...order]
        ..removeAt(from)
        ..insert(to, module),
    );
  }

  /// The order with the module at [from] dropped at [to], as a list that
  /// reorders by dragging reports it: [to] counts the dragged module's own
  /// slot, so a move down lands one before it.
  HomeLayout reordered(int from, int to) {
    if (from < 0 || from >= order.length) return this;
    var target = to > from ? to - 1 : to;
    target = target.clamp(0, order.length - 1);
    if (target == from) return this;
    final module = order[from];
    return _withOrder(
      [...order]
        ..removeAt(from)
        ..insert(target, module),
    );
  }

  /// [module] switched [on] or off. A module that cannot be hidden stays on.
  HomeLayout switched(HomeModule module, {required bool on}) {
    if (!module.hideable || module.audience != audience) return this;
    return HomeLayout._(
      audience: audience,
      order: order,
      hidden: on ? ({...hidden}..remove(module)) : {...hidden, module},
    );
  }

  /// What is stored: the version, the order, the modules switched off.
  String toJson() => jsonEncode({
    'v': version,
    'order': [for (final module in order) module.name],
    'hidden': [
      for (final module in HomeModule.of(audience))
        if (hidden.contains(module)) module.name,
    ],
  });

  HomeLayout _withOrder(List<HomeModule> next) =>
      HomeLayout._(audience: audience, order: next, hidden: hidden);

  /// The names in [raw] that are modules of [audience]'s Home, once each.
  static List<HomeModule> _modules(Object? raw, Audience audience) {
    if (raw is! List) return const [];
    final modules = <HomeModule>[];
    for (final name in raw) {
      if (name is! String) continue;
      final module = HomeModule.byName(name);
      if (module == null || module.audience != audience) continue;
      if (!modules.contains(module)) modules.add(module);
    }
    return modules;
  }

  /// [saved] and [hidden] with every module the registry has and they do not:
  /// each enters after the module that precedes it by default, so a module
  /// added to the app lands where it was designed to stand even on a Home
  /// arranged before it, and it starts on or off as the registry says.
  static HomeLayout _completed(
    Audience audience,
    List<HomeModule> saved,
    Set<HomeModule> hidden,
  ) {
    final defaults = HomeModule.orderedOf(audience);
    final order = [
      for (final module in saved)
        if (module.movable) module,
    ];
    final known = {...saved, ...hidden};
    final off = {
      for (final module in hidden)
        if (module.hideable) module,
    };
    for (var i = 0; i < defaults.length; i++) {
      final module = defaults[i];
      if (order.contains(module)) continue;
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final before = order.indexOf(defaults[j]);
        if (before >= 0) {
          at = before + 1;
          break;
        }
      }
      order.insert(at, module);
      if (!known.contains(module) && !module.defaultOn) off.add(module);
    }
    return HomeLayout._(audience: audience, order: order, hidden: off);
  }
}
