import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Activity's write toasts say why in the classification's words, and hand
/// the failure over as the toast's cause, so the glyph beside those words
/// takes the same tone they do: red only for a Seerr that did not answer.
void main() {
  Future<(Color?, String)> toastAfterDecline(
    WidgetTester tester,
    ConfigProfile profile,
  ) async {
    final harness = await ProfileHarness.start(profile);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => ActivityActions.declineRequest(
                  context,
                  ref,
                  instanceId: WorldIds.seerr,
                  requestId: 1,
                  title: 'Sintel',
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await harness.settle(tester);
    await tester.tap(find.text('Decline request'));
    await harness.settle(tester);

    final glyph = tester
        .widget<Icon>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Icon),
          ),
        )
        .color;
    final words = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ),
        )
        .data!;
    await harness.unmount(tester);
    return (glyph, words);
  }

  final theme = AppTheme.darkTheme();
  Color toned(StatusTone tone) => statusToneColor(
    theme.colorScheme,
    tone,
    surface: theme.snackBarTheme.backgroundColor,
  );

  testWidgets('P1, Seerr did not answer: "Seerr did not answer" in red', (
    tester,
  ) async {
    final (glyph, words) = await toastAfterDecline(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.seerr,
        ConnectionBehaviour.didNotAnswer,
      ),
    );
    expect(words, contains('Seerr did not answer'));
    expect(glyph, toned(StatusTone.error));
  });

  testWidgets('P1, Seerr refused the key: the refusal in amber', (
    tester,
  ) async {
    final (glyph, words) = await toastAfterDecline(
      tester,
      Profiles.p1.withBehaviour(WorldIds.seerr, ConnectionBehaviour.refusesKey),
    );
    expect(words, contains('Seerr answered but refused the key'));
    expect(glyph, toned(StatusTone.warning));
  });
}
