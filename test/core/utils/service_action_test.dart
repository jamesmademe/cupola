import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/settings_scope.dart';

const _copy = CapabilityCopy(
  service: ServiceKey.unraid,
  answered: 'This Unraid key can read.',
  scope: 'write access to VMs',
  hint: 'requires a key that can write VMs',
);

const _target = CapabilityTarget(connectionId: 'unraid', copy: _copy);

DioException _status(int code) {
  final request = RequestOptions(path: '/graphql');
  return DioException(
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: code),
    type: DioExceptionType.badResponse,
  );
}

/// Pumps a button that runs [error] through [runServiceAction], under a
/// router so the fix action has somewhere to land.
Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester, {
  required Object error,
  CapabilityTarget? capability,
}) async {
  final container = ProviderContainer(
    overrides: await settingsScopeOverrides(
      configured: const [ServiceKey.unraid],
    ),
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => runServiceAction(
                context,
                ref,
                action: () async => throw error,
                failureMessage: 'Could not start the VM',
                capability: capability,
              ),
              child: const Text('Start'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/settings/service/:service',
        builder: (context, state) => const Scaffold(body: Text('settings')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('Start'));
  // Past the toast's entrance, so its action is where a finger would find it.
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets('a refusal marks the connection and offers the fix', (
    tester,
  ) async {
    final (container, router) = await _pump(
      tester,
      error: _status(403),
      capability: _target,
    );

    expect(
      container.read(capabilityScopeProvider)['unraid'],
      const CapabilityGrant.refused(),
    );
    expect(find.text(_copy.refusal), findsOneWidget);
    // Not the failure toast: nothing broke.
    expect(find.textContaining('Could not start the VM'), findsNothing);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Update the key'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/settings/service/unraid?i=unraid');
  });

  testWidgets('a 401 marks nothing and reads as a failure', (tester) async {
    final (container, _) = await _pump(
      tester,
      error: _status(401),
      capability: _target,
    );

    expect(container.read(capabilityScopeProvider), isEmpty);
    expect(find.textContaining('Could not start the VM'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Update the key'), findsNothing);
  });

  testWidgets('without a capability a 403 is an ordinary failure', (
    tester,
  ) async {
    final (container, _) = await _pump(tester, error: _status(403));

    expect(container.read(capabilityScopeProvider), isEmpty);
    expect(find.textContaining('Could not start the VM'), findsOneWidget);
  });
}
