import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/pairing/data/pair_fetch.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

const _sender = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'http://192.168.1.10:7878',
      credential: 'radarr-key',
    ),
    ServiceInstance(
      id: 'sonarr',
      service: ServiceKey.sonarr,
      url: 'http://192.168.1.10:8989',
      credential: 'sonarr-key',
    ),
  ],
);

final _onLoopback = PairNetwork(
  findAddress: () async => InternetAddress.loopbackIPv4,
);

Future<ProviderContainer> _device({
  SettingsModel settings = const SettingsModel(),
  PairNetwork? network,
}) async {
  final scope = await settingsScope();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
      secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
      initialSettingsProvider.overrideWith((ref) => settings),
      initialOnboardingCompletedProvider.overrideWith((ref) => false),
      pairNetworkProvider.overrideWithValue(network ?? _onLoopback),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<T> _until<T>(
  ProviderContainer container,
  ProviderListenable<Object?> provider,
) async {
  final reached = Completer<T>();
  final sub = container.listen(provider, (_, next) {
    if (next is T && !reached.isCompleted) reached.complete(next);
  }, fireImmediately: true);
  try {
    return await reached.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

void main() {
  group('the sending device', () {
    test('opens a code for everything it has', () async {
      final sender = await _device(settings: _sender);
      sender.listen(pairOfferProvider, (_, _) {});
      await sender
          .read(pairOfferProvider.notifier)
          .start(from: PairDevice.iphone);
      final open = sender.read(pairOfferProvider) as PairOfferOpen;
      expect(open.package.connections, hasLength(2));
      expect(open.link.host, InternetAddress.loopbackIPv4);
    });

    test('says when it is on no home network', () async {
      final sender = await _device(
        settings: _sender,
        network: PairNetwork(findAddress: () async => null),
      );
      sender.listen(pairOfferProvider, (_, _) {});
      await sender
          .read(pairOfferProvider.notifier)
          .start(from: PairDevice.iphone);
      expect(sender.read(pairOfferProvider), isA<PairOfferNoNetwork>());
    });

    test('closes the code when the screen goes', () async {
      final sender = await _device(settings: _sender);
      final sub = sender.listen(pairOfferProvider, (_, _) {});
      await sender
          .read(pairOfferProvider.notifier)
          .start(from: PairDevice.iphone);
      final link = (sender.read(pairOfferProvider) as PairOfferOpen).link;
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final receiver = await _device();
      receiver.listen(pairReceiveProvider, (_, _) {});
      await receiver.read(pairReceiveProvider.notifier).receive(link);
      expect(
        receiver.read(pairReceiveProvider),
        isA<PairReceiveFailed>().having(
          (s) => s.failure,
          'failure',
          PairReceiveFailure.unreachable,
        ),
      );
    });

    test('a new code closes the one before', () async {
      final sender = await _device(settings: _sender);
      sender.listen(pairOfferProvider, (_, _) {});
      final offer = sender.read(pairOfferProvider.notifier);
      await offer.start(from: PairDevice.iphone);
      final first = (sender.read(pairOfferProvider) as PairOfferOpen).link;
      await offer.start(from: PairDevice.iphone);
      final second = (sender.read(pairOfferProvider) as PairOfferOpen).link;
      expect(second, isNot(first));
      final receiver = await _device();
      receiver.listen(pairReceiveProvider, (_, _) {});
      await receiver.read(pairReceiveProvider.notifier).receive(first);
      expect(receiver.read(pairReceiveProvider), isA<PairReceiveFailed>());
    });
  });

  group('the receiving device', () {
    test(
      'takes a code off the router, shows what it adds, and adds it',
      () async {
        final sender = await _device(settings: _sender);
        sender.listen(pairOfferProvider, (_, _) {});
        await sender
            .read(pairOfferProvider.notifier)
            .start(from: PairDevice.mac);
        final link = (sender.read(pairOfferProvider) as PairOfferOpen).link;

        final receiver = await _device();
        receiver.read(pendingPairProvider.notifier).hold(PairArrival(link));
        receiver.listen(pairReceiveProvider, (_, _) {});
        final preview = await _until<PairReceivePreview>(
          receiver,
          pairReceiveProvider,
        );
        expect(receiver.read(pendingPairProvider), isNull);
        expect(preview.plan.from, PairDevice.mac);
        expect(preview.plan.toAdd, hasLength(2));
        expect(sender.read(pairOfferProvider), isA<PairOfferSent>());

        await receiver.read(pairReceiveProvider.notifier).add();
        expect(receiver.read(pairReceiveProvider), isA<PairReceiveAdded>());
        final settings = receiver.read(currentSettingsProvider);
        expect(settings.instanceById('radarr')!.credential, 'radarr-key');
        expect(settings.instanceById('sonarr')!.credential, 'sonarr-key');
        expect(receiver.read(onboardingCompletedProvider), isTrue);
      },
    );

    test('says a link that did not arrive whole is not', () async {
      final receiver = await _device();
      receiver.read(pendingPairProvider.notifier).hold(const PairArrival(null));
      receiver.listen(pairReceiveProvider, (_, _) {});
      final failed = await _until<PairReceiveFailed>(
        receiver,
        pairReceiveProvider,
      );
      expect(failed.failure, PairReceiveFailure.notWhole);
      expect(failed.retryHelps, isFalse);
    });

    test('takes a code that arrives while the screen is open', () async {
      final sender = await _device(settings: _sender);
      sender.listen(pairOfferProvider, (_, _) {});
      await sender
          .read(pairOfferProvider.notifier)
          .start(from: PairDevice.iphone);
      final link = (sender.read(pairOfferProvider) as PairOfferOpen).link;

      final receiver = await _device();
      receiver.listen(pairReceiveProvider, (_, _) {});
      expect(receiver.read(pairReceiveProvider), isA<PairReceiveWaiting>());
      receiver.read(pendingPairProvider.notifier).hold(PairArrival(link));
      await _until<PairReceivePreview>(receiver, pairReceiveProvider);
    });

    test('a device off the network can try again', () async {
      final sender = await _device(settings: _sender);
      sender.listen(pairOfferProvider, (_, _) {});
      await sender
          .read(pairOfferProvider.notifier)
          .start(from: PairDevice.iphone);
      final link = (sender.read(pairOfferProvider) as PairOfferOpen).link;

      var offline = true;
      final receiver = await _device(
        network: PairNetwork(
          fetch: (link) async {
            if (offline) {
              throw const PairFetchException(PairFetchFailure.unreachable);
            }
            return const PairNetwork().fetch(link);
          },
        ),
      );
      receiver.listen(pairReceiveProvider, (_, _) {});
      final notifier = receiver.read(pairReceiveProvider.notifier);
      await notifier.receive(link);
      final failed = receiver.read(pairReceiveProvider) as PairReceiveFailed;
      expect(failed.retryHelps, isTrue);
      offline = false;
      await notifier.retry();
      expect(receiver.read(pairReceiveProvider), isA<PairReceivePreview>());
    });
  });
}
