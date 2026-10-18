import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/link_handoff.dart';

void main() {
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LinkHandoff.channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LinkHandoff.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on the Mac, the runner hears the router is ready once the '
      'first frame is drawn, not before', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    LinkHandoff.routerReadyWhenDrawn();
    expect(calls, isEmpty);

    await tester.pumpWidget(const SizedBox());
    expect(calls, ['routerReady']);

    // One signal per start: later frames say nothing more.
    await tester.pump();
    expect(calls, ['routerReady']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('elsewhere the router reads its links itself, so nothing is '
      'said', (tester) async {
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      LinkHandoff.routerReadyWhenDrawn();
      await tester.pumpWidget(const SizedBox());
    }
    debugDefaultTargetPlatformOverride = null;
    expect(calls, isEmpty);
  });

  testWidgets('a runner without the channel is not an error', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LinkHandoff.channel, null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    LinkHandoff.routerReadyWhenDrawn();
    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
