import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/connection_badge.dart';

void main() {
  testWidgets('ConnectionBadge rounds its corners on the radius token', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: Center(
            child: ConnectionBadge(label: 'v3', accent: AppColors.radarr),
          ),
        ),
      ),
    );

    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(ConnectionBadge),
        matching: find.byType(Container),
      ),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(DesignTokens.radiusXs2),
    );
  });
}
