import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_snapshot_cover.dart';
import 'package:cupola/core/widgets/service_ring.dart';

void main() {
  testWidgets('covers the app while it is not active on a phone', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: AppSnapshotCover(child: Text('the app'))),
      );

      expect(find.byType(CupolaMark), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.byType(CupolaMark), findsOneWidget);
      expect(find.text('the app'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byType(CupolaMark), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('does not cover Android, which has the real flag', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: AppSnapshotCover(child: Text('the app'))),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.byType(CupolaMark), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  testWidgets('does not cover a desktop window that merely lost focus', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: AppSnapshotCover(child: Text('the app'))),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.byType(CupolaMark), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });
}
