/// What a media server answers about a title is read again only when its
/// own connection changes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../test_helpers/settings_scope.dart';

void main() {
  test('a settings write that does not touch the connection asks nothing '
      'again', () async {
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(),
    );
    addTearDown(container.dispose);
    const source = (key: MediaKey.movie(653), connectionId: 'cabin');

    var updates = 0;
    container.listen(mediaStreamCopyProvider(source), (_, _) => updates++);
    // No such connection here: the first read fails, and that is all.
    await expectLater(
      container.read(mediaStreamCopyProvider(source).future),
      throwsArgumentError,
    );
    updates = 0;

    final settings = container.read(currentSettingsProvider);
    await container
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(region: 'DE'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentSettingsProvider).region, 'DE');
    expect(updates, 0);
  });
}
