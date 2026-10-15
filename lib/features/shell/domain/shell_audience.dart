import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';

/// Who the shell is drawn for: [audienceProvider], held while the app is in
/// use.
///
/// The bar and the routes a person may reach follow the audience, but never
/// under the person's finger: an operator who signs in to a requester's Seerr
/// account in Settings keeps the bar they are using until the app next comes
/// back to the foreground, and only then does the control room leave it. The
/// gate inside each screen follows the audience at once
/// ([audienceProvider]); this is the shell's hold, documented there.
///
/// Taken afresh when the app returns to the foreground and when onboarding
/// finishes, the two moments nothing is under the finger.
final shellAudienceProvider = NotifierProvider<ShellAudienceNotifier, Audience>(
  ShellAudienceNotifier.new,
);

class ShellAudienceNotifier extends Notifier<Audience> {
  @override
  Audience build() {
    ref.listen<bool>(appInForegroundProvider, (previous, next) {
      if (next && previous == false) _take();
    });
    ref.listen<bool>(onboardingCompletedProvider, (previous, next) {
      if (next) _take();
    });
    return ref.read(audienceProvider);
  }

  void _take() => state = ref.read(audienceProvider);

  /// Takes the audience now, at a moment nothing is under the finger: the
  /// first run's sign-in, whose screen goes away as it is taken, when the
  /// way in was already over (the Home at zero's door).
  void take() => _take();
}
