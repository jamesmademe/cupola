import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The rule this file enforces: **repeating work belongs to the page on screen.**
///
/// It is a source scan rather than a review habit because the failure it catches
/// is invisible in a diff. A `Timer.periodic` and the page that should own it
/// live in different files, so a new poller reads as three correct lines in a
/// provider — and only shows up as a phone that talks to five services from a
/// tab nobody is looking at.
///
/// Three checks, each with a message that says what to do instead. If one fires
/// on work that genuinely is not a poller, the exception lists below are the
/// place to say so, in the diff, with a reason.
void main() {
  /// The only file allowed to construct a repeating timer.
  const gatedPollFile = 'lib/core/lifecycle/gated_poll.dart';

  /// Repeating work that is not polling, and must not be gated.
  ///
  /// Both are once-a-second repaints of an elapsed-time readout inside a
  /// modal sheet. Neither touches the network, and the second accumulates a
  /// second per tick rather than reading the clock: pausing it would save
  /// nothing and would make the duration it displays wrong. A rule that forced
  /// them through the polling primitive would buy a tidier scan and a bug.
  const uiClocks = {
    'lib/core/widgets/interactive_search_sheet.dart',
    'lib/features/release_search/presentation/release_search_sheet.dart',
  };

  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  test('lib/ has files to scan', () {
    expect(libFiles, isNotEmpty);
  });

  test('Timer.periodic and Stream.periodic live only behind the gate', () {
    final offenders = <String>[];
    for (final file in libFiles) {
      final path = file.path;
      if (path == gatedPollFile || uiClocks.contains(path)) continue;
      final source = file.readAsStringSync();
      if (source.contains('Timer.periodic') ||
          source.contains('Stream.periodic')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A periodic timer outside $gatedPollFile is a poller with no gate: it '
          'keeps running from a hidden tab, from under a pushed page and from a '
          'backgrounded app. Use `Ref.gatedPoll` inside an autoDispose provider '
          'the page watches with `ref.watchWhileLive`, or `VisibilityPoller` / '
          '`GatedPollTimer` for a page that owns its own timer. If the work is '
          'not polling at all, add it to `uiClocks` in this test with the '
          'reason.',
    );
  });

  test('a polling provider is only ever watched through the gate', () {
    // Matches `ref.watch(somethingPollingProvider)` and its `...Tick...` kin —
    // the naming every poller in the app follows.
    final ungatedWatch = RegExp(
      r'ref\.watch\(\s*\w*(?:Polling|Tick)\w*Provider',
    );
    final offenders = <String>[];
    for (final file in libFiles) {
      if (ungatedWatch.hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A plain `ref.watch` of a polling provider keeps it alive for as long '
          'as the widget is mounted — and since the four tabs became branches, '
          'a widget stays mounted long after it stops being read. Use '
          '`ref.watchWhileLive(context, thatProvider)` instead.',
    );
  });

  test('every gated poller has an id of its own', () {
    final idPattern = RegExp(r"""id:\s*'([^']+)'""");
    final ids = <String, List<String>>{};
    for (final file in libFiles) {
      if (file.path == gatedPollFile) continue;
      final source = file.readAsStringSync();
      if (!source.contains('gatedPoll(') &&
          !source.contains('GatedPollTimer(') &&
          !source.contains('VisibilityPoller(') &&
          !source.contains('RefreshOnReturn(')) {
        continue;
      }
      for (final match in idPattern.allMatches(source)) {
        ids.putIfAbsent(match.group(1)!, () => []).add(file.path);
      }
    }

    final duplicated = {
      for (final entry in ids.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    };

    expect(
      duplicated,
      isEmpty,
      reason:
          'Two of these sharing an id share a last-tick record. Between two '
          'pollers, one decides the other had just run and skips its catch-up. '
          'Between a poller and a RefreshOnReturn it is worse and quieter: the '
          "poller's ticks keep resetting the staleness clock, so the page never "
          'looks old enough to refresh on return and nothing ever says so. Ids '
          'are per unit of work — see `qbittorrent.detail.\$hash`, which is per '
          'torrent for exactly this reason.',
    );

    // Not a rule, a tripwire: if the app ever has no gated work left, this test
    // is silently guarding nothing.
    expect(ids, isNotEmpty, reason: 'the scan found no gated pollers at all');
  });
}
