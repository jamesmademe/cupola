import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_overview_provider.dart';

/// The folding rules of the Dockge Overview, exercised as the pure functions
/// they are — no container, no socket, no clock.
///
/// No clock because there is nothing to clock: `stackList` carries no
/// timestamp, which is why this page has no window rule to test the boundaries
/// of. That absence is asserted here too, in the one place it shows — a fault
/// row that prints no age rather than an invented one.
void main() {
  group('the census', () {
    test('buckets every state, and inactive folds Dockge\'s two spellings', () {
      final census = dockgeStackCensus([
        _stack('media'),
        _stack('downloads'),
        _stack('bazarr', status: DockgeStackStatus.exited),
        _stack('archive', status: DockgeStackStatus.createdFile),
        _stack('templates', status: DockgeStackStatus.createdStack),
        _stack('ghost', status: DockgeStackStatus.unknown),
      ]);

      expect(census.total, 6);
      expect(census.running, 2);
      expect(census.stopped, 1);
      // `CREATED_FILE` and `CREATED_STACK` are one reading: Dockge prints
      // "Inactive" for both, and the difference is not one the user acts on.
      expect(census.inactive, 2);
      // `UNKNOWN` stays apart. "Not started" is a fact; "we do not know" is
      // not, and folding the second into the first would print the fact.
      expect(census.unknown, 1);
    });

    test('an empty push is a census of zeroes, not a missing one', () {
      // The distinction the screen depends on: a server that answered with no
      // stacks reports 0, and a server that did not answer never reaches this
      // function at all — the section prints an em dash instead.
      final census = dockgeStackCensus(const []);
      expect(census.total, 0);
      expect(census.stopped, 0);
    });
  });

  group('not running', () {
    test('a stopped stack is backlog: one neutral aggregate, never amber', () {
      final rows = dockgeIdleGroups([
        _stack('media'),
        _stack('bazarr', status: DockgeStackStatus.exited),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.tone, StatusTone.neutral);
      expect(rows.single.headline, '1 stack is stopped');
      // Dockge does not say whether the stop was intended, so the row says so.
      expect(rows.single.detail, 'bazarr · Dockge does not say why');
    });

    test('a stopped row states no age, because nothing here is dated', () {
      final rows = dockgeIdleGroups([
        _stack('bazarr', status: DockgeStackStatus.exited),
      ]);

      // Nothing in `stackList` carries a time or an exit code, so the row
      // prints neither. An invented window is worse than none.
      expect(rows.single.detail, isNot(contains('ago')));
      expect(rows.single.detail, isNot(contains('exit code')));
    });

    test('a stopped group names its stacks and counts the rest', () {
      final rows = dockgeIdleGroups([
        for (final name in ['Zulu', 'alpha', 'bravo', 'charlie'])
          _stack(name, status: DockgeStackStatus.exited),
      ]);

      // Sorted case-insensitively, and past three names the count replaces the
      // rest rather than a dotted list that simply stops.
      expect(rows.single.headline, '4 stacks are stopped');
      expect(
        rows.single.detail,
        'alpha, bravo, charlie and 1 more · Dockge does not say why',
      );
    });

    test('nine stopped stacks are one row, nothing capped out of sight', () {
      final rows = dockgeIdleGroups([
        for (var i = 0; i < 9; i++)
          _stack('stack-$i', status: DockgeStackStatus.exited),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.headline, '9 stacks are stopped');
    });

    test('an inactive stack is backlog, and it is neutral', () {
      final rows = dockgeIdleGroups([
        _stack('archive', status: DockgeStackStatus.createdFile),
        _stack('templates', status: DockgeStackStatus.createdStack),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.tone, StatusTone.neutral);
      expect(rows.single.headline, '2 stacks are inactive');
      expect(
        rows.single.detail,
        'archive, templates · brought down, or never started',
      );
    });

    test('one inactive stack says so in the singular', () {
      final rows = dockgeIdleGroups([
        _stack('archive', status: DockgeStackStatus.createdStack),
      ]);

      expect(rows.single.headline, '1 stack is inactive');
    });

    test('an unknown stack is aggregated, never flagged', () {
      final rows = dockgeIdleGroups([
        _stack('ghost', status: DockgeStackStatus.unknown),
      ]);

      expect(rows.single.tone, StatusTone.neutral);
      expect(rows.single.headline, '1 stack reports no state');
      expect(rows.single.detail, 'ghost · Dockge did not say');
    });

    test('stopped, inactive and unknown come in that order, and running stacks '
        'appear in none', () {
      final rows = dockgeIdleGroups([
        _stack('archive', status: DockgeStackStatus.createdFile),
        _stack('media'),
        _stack('bazarr', status: DockgeStackStatus.exited),
        _stack('ghost', status: DockgeStackStatus.unknown),
      ]);

      expect(rows.map((row) => row.headline), [
        '1 stack is stopped',
        '1 stack is inactive',
        '1 stack reports no state',
      ]);
      expect(rows.every((row) => row.tone == StatusTone.neutral), isTrue);
    });

    test('an aggregate names three stacks and counts the rest', () {
      final rows = dockgeIdleGroups([
        for (final name in ['a', 'b', 'c', 'd', 'e'])
          _stack(name, status: DockgeStackStatus.createdFile),
      ]);

      // "and 2 more", not a fourth comma: a list that simply stops reads as
      // truncated, and the count is the half that cannot be dropped.
      expect(
        rows.single.detail,
        'a, b, c and 2 more · brought down, or never started',
      );
    });
  });

  group('the stacks preview', () {
    test('draws only what is running, sorted by name', () {
      final rows = dockgeRunningRows([
        _stack('npm'),
        _stack('bazarr', status: DockgeStackStatus.exited),
        _stack('immich'),
      ]);

      expect(rows.map((row) => row.name), ['immich', 'npm']);
      expect(rows.every((row) => row.tone == StatusTone.success), isTrue);
    });

    test('spells the state out, because colour is not information', () {
      final rows = dockgeRunningRows([
        _stack('immich', tags: ['media']),
      ]);

      expect(rows.single.detail, 'running · media');
      expect(rows.single.spoken, 'immich, running, media');
    });

    test('never prints a claim that defaults to the accusing side', () {
      // `isManagedByDockge` parses as `json[...] == true`, so a push that omits
      // the key reads false for every stack. A row saying "not managed by
      // Dockge" under all of them would be a fabrication, so it is not said.
      final rows = dockgeRunningRows([
        _stack('immich', isManagedByDockge: false),
      ]);

      expect(rows.single.detail, 'running');
    });

    test('is capped', () {
      final rows = dockgeRunningRows([
        for (var i = 0; i < 12; i++) _stack('stack-$i'),
      ], limit: 5);

      expect(rows, hasLength(5));
    });
  });

  group('the agents', () {
    test('the hub names itself by what it is, not by an address', () {
      final rows = dockgeAgentRows([
        DockgeAgent.local,
        const DockgeAgent(endpoint: 'nas.lan:5001', name: 'nas'),
      ], selectedEndpoint: '');

      expect(
        rows.first.detail,
        'this connection · online · showing its stacks',
      );
      expect(rows.first.isSelected, isTrue);
    });

    test('the selected agent is the one the figures above came off', () {
      final rows = dockgeAgentRows([
        DockgeAgent.local,
        const DockgeAgent(endpoint: 'nas.lan:5001', name: 'nas'),
      ], selectedEndpoint: 'nas.lan:5001');

      expect(rows.first.isSelected, isFalse);
      expect(rows.last.isSelected, isTrue);
      expect(rows.last.detail, 'nas.lan:5001 · online · showing its stacks');
    });

    test('an agent that is not answering is the one red in this feature', () {
      final rows = dockgeAgentRows([
        DockgeAgent.local,
        const DockgeAgent(
          endpoint: 'nas.lan:5001',
          name: 'nas',
          status: 'offline',
        ),
      ], selectedEndpoint: '');

      // Red means a connection that did not answer, and that is exactly what
      // this is. `connecting` has not failed yet, so it reads informational.
      expect(rows.last.tone, StatusTone.error);
    });

    test('every instance is drawn, because none of them has anywhere else '
        'to be reported', () {
      // The Agents section is the only region with no "see the rest" tab, so a
      // cap here would drop agents six and up off the app entirely — and its
      // header would then state the sample's own length as the total.
      final rows = dockgeAgentRows([
        DockgeAgent.local,
        for (var i = 1; i < 7; i++)
          DockgeAgent(endpoint: 'node-$i:5001', name: 'node-$i'),
      ], selectedEndpoint: '');

      expect(rows, hasLength(7));
      expect(rows.last.name, 'node-6');
    });

    test('speaks one sentence per instance', () {
      final rows = dockgeAgentRows([
        const DockgeAgent(
          endpoint: 'nas.lan:5001',
          name: 'nas',
          status: 'connecting',
        ),
      ], selectedEndpoint: '');

      expect(rows.single.tone, StatusTone.info);
      expect(rows.single.spoken, 'nas, nas.lan:5001, connecting');
    });
  });
}

DockgeStack _stack(
  String name, {
  DockgeStackStatus status = DockgeStackStatus.running,
  List<String> tags = const [],
  bool isManagedByDockge = true,
}) => DockgeStack(
  name: name,
  status: status,
  tags: tags,
  isManagedByDockge: isManagedByDockge,
);
