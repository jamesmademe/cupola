import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/secure_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<bool> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.matthwlabs.cupola/secure_screen'),
      (call) async {
        if (call.method == 'setSecure') {
          calls.add((call.arguments as Map)['secure'] as bool);
        }
        return null;
      },
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.matthwlabs.cupola/secure_screen'),
      null,
    );
  });

  testWidgets('sets the flag while the screen is mounted and clears it after', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SecureScreen(child: Text('key'))),
    );
    await tester.pump();

    expect(calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    await tester.pump();

    expect(calls, [true, false]);
  });

  testWidgets('keeps the flag while a second secure screen overlaps', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SecureScreen(child: SecureScreen(child: Text('nested'))),
      ),
    );
    await tester.pump();

    // The inner screen is the second holder; neither may clear the flag.
    expect(calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    await tester.pump();

    expect(calls, [true, false]);
  });
}
