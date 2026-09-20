import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

void main() {
  testWidgets('compact chrome truncates a long breadcrumb without overflow', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final router = GoRouter(
        initialLocation: '/settings/background-search',
        routes: [
          GoRoute(
            path: '/settings/background-search',
            builder: (_, _) => const WindowChrome(inspectorOpen: false),
          ),
        ],
      );

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Background search'), findsOneWidget);

      router.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
