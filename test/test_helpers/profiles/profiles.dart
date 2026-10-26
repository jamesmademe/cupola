/// The demo world (`lib/demo/world/`) as a test pumps it: the configuration
/// profiles, their fake network, and the harness that makes one live.
///
/// ```dart
/// await pumpWithProfile(tester, Profiles.p6, child: const StackScreen());
/// ```
///
/// See `lib/demo/world/README.md` for what each profile is for.
library;

export 'package:cupola/demo/world/profiles.dart';

export 'profile_harness.dart';
