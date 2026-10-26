import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// How the app goes into the demo and out of it. Each way swaps the whole
/// app (`runApp`), so the demo's container and the real one never live side
/// by side; `main.dart` provides it.
class DemoDoor {
  const DemoDoor({required this.enter, required this.leave});

  /// Opens the demo over an app whose settings are `leaving`; refused
  /// ([DemoRefused]) when they hold a connection.
  final Future<void> Function(SettingsModel leaving) enter;

  /// Ends `session` and starts the app again from its real stores.
  final Future<void> Function(DemoSession session) leave;
}

/// The door, or null where there is no app to swap: a test's container, the
/// run with the app off the screen.
final demoDoorProvider = Provider<DemoDoor?>((ref) => null);
