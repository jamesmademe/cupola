import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';

DockgeStack _stack(String name) =>
    DockgeStack(name: name, status: DockgeStackStatus.running);

/// A client whose socket is scripted: the list the previous connection left
/// behind, and what this connection pushes back when it is asked for its list.
class _ScriptedDockge extends DockgeClient {
  _ScriptedDockge({
    required List<DockgeStack> previousConnectionList,
    this.answersRequests = true,
  }) : _latest = previousConnectionList,
       super(baseUrl: 'https://dockge.example.com');

  final bool answersRequests;
  final _pushes = StreamController<List<DockgeStack>>.broadcast();
  List<DockgeStack> _latest;
  var requests = 0;
  var connections = 0;

  /// What the server pushes for the connection the service just opened.
  List<DockgeStack> freshList = const [];

  @override
  List<DockgeStack> get latestStacks => _latest;

  @override
  Stream<List<DockgeStack>> get stackListStream => _pushes.stream;

  @override
  Future<void> ensureConnected() async {
    connections++;
  }

  @override
  Future<void> requestStackList() async {
    requests++;
    if (!answersRequests) return;
    Timer(const Duration(milliseconds: 200), () {
      _latest = freshList;
      _pushes.add(freshList);
    });
  }
}

void main() {
  group('DockgeService.fetchStacks after a reconnect', () {
    testWidgets('asks this connection and answers with its push', (
      tester,
    ) async {
      final client = _ScriptedDockge(previousConnectionList: [_stack('old')])
        ..freshList = [_stack('fresh')];
      final service = DockgeService(client);
      List<DockgeStack>? answer;

      service.fetchStacks().then((stacks) => answer = stacks);
      await tester.pump(const Duration(milliseconds: 250));

      expect(client.connections, 1);
      expect(client.requests, 1, reason: 'this connection is asked');
      expect(answer?.map((s) => s.name), ['fresh']);
    });

    testWidgets('uses the cached list only once the server has been silent '
        'for five seconds', (tester) async {
      final client = _ScriptedDockge(
        previousConnectionList: [_stack('cached')],
        answersRequests: false,
      );
      final service = DockgeService(client);
      List<DockgeStack>? answer;
      Object? error;

      service.fetchStacks().then<void>(
        (stacks) => answer = stacks,
        onError: (Object e) => error = e,
      );

      await tester.pump(const Duration(seconds: 4));
      expect(answer, isNull, reason: 'not before the wait is over');
      expect(error, isNull);

      await tester.pump(const Duration(seconds: 2));
      expect(answer?.map((s) => s.name), ['cached']);
      expect(client.requests, 1);
    });

    testWidgets('a silent server with nothing cached is an error, not an '
        'empty list', (tester) async {
      final client = _ScriptedDockge(
        previousConnectionList: const [],
        answersRequests: false,
      );
      final service = DockgeService(client);
      List<DockgeStack>? answer;
      Object? error;

      service.fetchStacks().then<void>(
        (stacks) => answer = stacks,
        onError: (Object e) => error = e,
      );
      await tester.pump(const Duration(seconds: 6));

      expect(answer, isNull);
      expect(error, isA<DockgeException>());
    });
  });
}
