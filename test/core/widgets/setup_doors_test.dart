import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/setup_doors.dart';

/// The ways in the Welcome and the Home at zero share: three doors, each said
/// under it on a phone and as its own hint always.
Widget _host({
  double textScale = 1,
  VoidCallback? onSetUp,
  VoidCallback? onCopy,
  VoidCallback? onSignIn,
}) => MaterialApp(
  theme: AppTheme.darkTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: SetupDoors(
        onSetUp: onSetUp ?? () {},
        onCopy: onCopy ?? () {},
        onSignIn: onSignIn ?? () {},
      ),
    ),
  ),
);

Finder _door(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

void main() {
  testWidgets('the copy door comes last, a link under the two buttons, and '
      'says what it is for', (tester) async {
    await tester.pumpWidget(_host());

    final setUp = tester.getTopLeft(find.text('Set up a service')).dy;
    final signIn = tester.getTopLeft(find.text('I have a Seerr account')).dy;
    final copy = tester.getTopLeft(find.text('Copy from another device')).dy;
    expect(setUp, lessThan(signIn));
    expect(signIn, lessThan(copy));
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
    expect(
      find.text('Point the camera at the code on your other device'),
      findsOneWidget,
    );
    // The hint is the door's, under it.
    final hint = tester.getTopLeft(find.text(SetupDoors.copyHint)).dy;
    expect(hint, greaterThan(copy));
  });

  testWidgets('each door opens its own way', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _host(
        onSetUp: () => opened.add('set up'),
        onCopy: () => opened.add('copy'),
        onSignIn: () => opened.add('sign in'),
      ),
    );

    await tester.tap(find.text('Copy from another device'));
    await tester.tap(find.text('I have a Seerr account'));
    await tester.tap(find.text('Set up a service'));

    expect(opened, ['copy', 'sign in', 'set up']);
  });

  testWidgets('the copy door is text, not a second fill', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Copy from another device'),
        matching: find.bySubtype<TextButton>(),
      ),
      findsOneWidget,
    );
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('every door keeps its 44pt floor on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_host());
        for (final label in [
          'Set up a service',
          'Copy from another device',
          'I have a Seerr account',
        ]) {
          expect(
            tester.getSize(_door(label)).height,
            greaterThanOrEqualTo(44),
            reason: label,
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  group('past the reading size where two buttons stop sharing a line', () {
    testWidgets('the lines are not drawn, and each is still the hint of its '
        'door', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(textScale: 2));

      for (final line in [
        SetupDoors.setUpHint,
        SetupDoors.copyHint,
        SetupDoors.signInHint,
      ]) {
        expect(find.text(line), findsNothing);
      }
      expect(
        find.semantics.byLabel('Copy from another device'),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hint: SetupDoors.copyHint,
        ),
      );
      handle.dispose();
    });
  });
}
