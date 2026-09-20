import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/arr_calendar_screen.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  testWidgets(
    'calendar and arr activity tabs stop before their providers when unconfigured',
    (tester) async {
      for (final screen in const <Widget>[
        ArrCalendarScreen(service: ServiceKey.radarr),
        ArrTabScreen(serviceType: ServiceType.movies, mode: ArrTabMode.queue),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentSettingsProvider.overrideWith(
                (ref) => const SettingsModel(),
              ),
            ],
            child: MaterialApp(home: screen),
          ),
        );
        await tester.pump();

        expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      }
    },
  );
}
