@Tags(['catalog'])
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/shell/domain/startup_failure.dart';
import 'package:cupola/features/shell/presentation/startup_failure_page.dart';

import 'catalog.dart';

StartupFailurePage _page(StartupFailure failure) => StartupFailurePage(
  failure: failure,
  onRetry: () async {},
  onForgetKeys: () async {},
);

final _refused = PlatformException(
  code: '-25308',
  message: 'User interaction is not allowed.',
);

void main() {
  catalogCard(
    'StartupFailurePage',
    scenes: [
      CatalogScene(
        'Connections · the Keychain refused the read: the cause once, Retry '
        'in the fault fill, Forget saved keys in ink, the platform\'s words '
        'behind Why?',
        (_) => _page(
          StartupFailure(
            step: StartupStep.connections,
            error: _refused,
            platform: TargetPlatform.iOS,
          ),
        ),
        width: 390,
        height: 520,
      ),
      CatalogScene(
        'Forgetting failed · the store would not even be emptied: on Linux, '
        'what to start',
        (_) => _page(
          StartupFailure(
            step: StartupStep.forgettingKeys,
            error: _refused,
            platform: TargetPlatform.linux,
          ),
        ),
        width: 390,
        height: 520,
      ),
      CatalogScene(
        'Connections · the read never answered within the limit: no Why? and '
        'no forgetting, the sentence says all it knows',
        (_) => _page(
          StartupFailure(
            step: StartupStep.connections,
            error: TimeoutException(null),
            platform: TargetPlatform.iOS,
          ),
        ),
        width: 390,
        height: 520,
      ),
      CatalogScene(
        'Connections on Linux · a keyring that may still be locked',
        (_) => _page(
          StartupFailure(
            step: StartupStep.connections,
            error: _refused,
            platform: TargetPlatform.linux,
          ),
        ),
        width: 390,
        height: 520,
      ),
      CatalogScene(
        'Settings file · an error the step does not explain: the headline, '
        'Retry, and Why?',
        (_) => _page(
          StartupFailure(
            step: StartupStep.preferences,
            error: StateError('Bad state: unreadable preferences'),
          ),
        ),
        width: 390,
        height: 520,
      ),
      CatalogScene(
        'Text at 200% · the Keychain refusal',
        (_) => _page(
          StartupFailure(
            step: StartupStep.connections,
            error: _refused,
            platform: TargetPlatform.iOS,
          ),
        ),
        width: 390,
        height: 700,
        textScale: catalogTextScale,
      ),
    ],
  );
}
