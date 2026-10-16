import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationCacheDirectory;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/last_known/last_known_store.dart';

import 'package:cupola/core/network/network_change.dart';
import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/network/unanswered_addresses.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/platform/desktop_window.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/widgets/themed_system_bars.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_refusal_store.dart';
import 'package:cupola/features/release_search/data/release_search_bootstrap.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/route_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/startup_failure.dart';
import 'package:cupola/features/shell/presentation/settings_back_claim.dart';
import 'package:cupola/features/shell/presentation/startup_failure_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prepares the frameless window, still hidden: it is shown once something
  // is drawn in it (see [_start]), so no await below can leave a black
  // rectangle on the screen. Inert on iOS and Android.
  await DesktopWindow.ensureReady();
  _registerBundledFontLicense();
  await _start();
}

/// Reads what the app needs, then draws it, or draws why it could not.
///
/// Every read before `runApp` is inside [attemptStartup]: one that throws or
/// never answers is a page that says so, with Retry, instead of a window (or a
/// launch screen) that stays as it is for good. Retry runs this again from the
/// top, and `runApp` replaces whichever app is drawn.
Future<void> _start() async {
  // Read beside the settings, never before them: the Home's last drawing
  // is what makes the first frame useful, and it must not make it late.
  final lastKnown = _openLastKnown();
  final outcome = await attemptStartup((reach) async {
    reach(StartupStep.preferences);
    final prefs = await SharedPreferences.getInstance();
    final secureSettingsStore = createSecureSettingsStore();
    final settingsService = SettingsService(prefs, secureSettingsStore);

    // Unconditional, including for a user who has background search switched
    // off. It is also what purges the records the last session left behind.
    // See its own doc.
    await configureBackgroundSearch();

    reach(StartupStep.connections);
    await settingsService.migrateFromPlaintext();
    final initialSettings = await _loadInitialSettings(settingsService);
    final onboardingCompleted = await settingsService.loadOnboardingComplete();

    return _buildProviderOverrides(
      prefs: prefs,
      secureSettingsStore: secureSettingsStore,
      initialSettings: initialSettings,
      activeInstances: settingsService.loadActiveInstances(),
      onboardingCompleted: onboardingCompleted,
      lastKnown: await lastKnown,
    );
  });

  switch (outcome) {
    case StartupReady(value: final overrides):
      runApp(ProviderScope(overrides: overrides, child: const CupolaApp()));
    case StartupFailed(:final failure):
      runApp(
        StartupFailureApp(
          failure: failure,
          onRetry: _start,
          onForgetKeys: _forgetKeysAndStart,
        ),
      );
  }
  DesktopWindow.showWhenDrawn();
}

/// The Home's last drawings (`LastKnownStore`), from the system's cache
/// folder; an empty store when there is none, when the folder cannot be read,
/// or when reading it takes longer than a start can spare.
///
/// Written once a burst of answers has passed, and when the app leaves the
/// screen, which may be the last chance this run gets.
Future<LastKnownStore> _openLastKnown() async {
  try {
    final folder = await getApplicationCacheDirectory();
    final store = await LastKnownStore.open(
      File('${folder.path}/last_known.json'),
    ).timeout(const Duration(milliseconds: 400));
    _lastKnownListener?.dispose();
    _lastKnownListener = AppLifecycleListener(
      onHide: store.flush,
      onDetach: store.flush,
    );
    return store;
  } catch (_) {
    return LastKnownStore.memory();
  }
}

AppLifecycleListener? _lastKnownListener;

/// Empties secure storage, keeping every address and preference, then
/// starts again; a store that will not even be emptied is said on the same
/// page, as its own failure.
Future<void> _forgetKeysAndStart() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await SettingsService(prefs, createSecureSettingsStore()).forgetSecrets();
  } catch (error) {
    runApp(
      StartupFailureApp(
        failure: StartupFailure(step: StartupStep.forgettingKeys, error: error),
        onRetry: _start,
      ),
    );
    return;
  }
  await _start();
}

/// The bundled font families and the SIL OFL 1.1 each one ships under.
///
/// One entry per family, because each licence names its own copyright holder:
/// a single merged entry would credit the wrong authors for two of the three.
const Map<String, String> bundledFontLicenses = {
  'Bricolage Grotesque': 'assets/fonts/BricolageGrotesque-OFL.txt',
  'Onest': 'assets/fonts/Onest-OFL.txt',
  'Geist Mono': 'assets/fonts/GeistMono-OFL.txt',
};

/// Puts each bundled font's SIL OFL 1.1 into the licence page Flutter builds
/// from [LicenseRegistry].
///
/// The registry only knows about licences declared in package metadata, and a
/// font dropped into `assets/` has none, so the one obligation the OFL puts on
/// a binary that bundles the font, that its licence travel with it, would go
/// unmet in every shipped build. Registered before `runApp` because the
/// registry is read lazily and the callback must already be there when the
/// licence page asks.
void _registerBundledFontLicense() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: family, value: asset)
        in bundledFontLicenses.entries) {
      yield LicenseEntryWithLineBreaks(<String>[
        family,
      ], await rootBundle.loadString(asset));
    }
  });
}

Future<SettingsModel> _loadInitialSettings(SettingsService settingsService) {
  return settingsService.loadSettings();
}

// `Override` has no public name: riverpod declares it in `src/core/override.dart`
// and `flutter_riverpod`'s export list leaves it out, so the return type cannot
// be written without an implementation import. Same reason as the
// `implementation_imports` ignores elsewhere in the tree.
// ignore: strict_top_level_inference
_buildProviderOverrides({
  required SharedPreferences prefs,
  required SecureSettingsStore secureSettingsStore,
  required SettingsModel initialSettings,
  required Map<ServiceKey, String> activeInstances,
  required bool onboardingCompleted,
  required LastKnownStore lastKnown,
}) {
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    lastKnownStoreProvider.overrideWithValue(lastKnown),
    secureSettingsStoreProvider.overrideWithValue(secureSettingsStore),
    // A refused qBittorrent sign-in outlives the run, so a relaunch does not
    // spend another of the five attempts its ban allows.
    qbittorrentRefusalStoreProvider.overrideWithValue(
      SecureQbittorrentRefusalStore(secureSettingsStore),
    ),
    initialSettingsProvider.overrideWithValue(initialSettings),
    initialActiveInstancesProvider.overrideWithValue(activeInstances),
    initialOnboardingCompletedProvider.overrideWithValue(onboardingCompleted),
  ];
}

class CupolaApp extends ConsumerWidget {
  const CupolaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Each Seerr account's permissions, read again at start and when the
    // app comes back with them stale.
    ref.watch(seerrAccountKeeperProvider);
    // Moves each connection with an address away from home to the address
    // that answers: at start, on resume, when one stops answering.
    ref.watch(routeProbeProvider);
    // Says when the phone's network changes with the app open, so the route
    // and the connections' readouts are asked again.
    ref.watch(networkChangeWatchProvider);

    // Keeps `CertTrustRegistry` in sync for the leaf image widgets that
    // cannot watch a provider themselves; see its doc for why. The `read`
    // populates the snapshot before the first poster ever asks (`listen`
    // alone only fires on a *change*); `listen`, registered every build per
    // the standard `ref.listen` idiom, keeps it current after that.
    CertTrustRegistry.update(
      ref.read(currentSettingsProvider).trustedCertificates,
    );
    ref.listen(
      currentSettingsProvider.select((s) => s.trustedCertificates),
      (previous, next) => CertTrustRegistry.update(next),
    );
    // The same bridge for each connection's access, which an arr's artwork
    // needs as much as its API calls: see `ConnectionAccessRegistry`.
    ConnectionAccessRegistry.update(
      ref.read(currentSettingsProvider).accessHeadersByAddress,
    );
    ref.listen(
      currentSettingsProvider.select((s) => s.accessHeadersByAddress),
      (previous, next) => ConnectionAccessRegistry.update(next),
    );
    // And for the connections neither of whose addresses answered the route
    // probe, so a client's next request names both: see
    // `UnansweredAddresses`.
    UnansweredAddresses.update(ref.read(unansweredAddressesProvider));
    ref.listen(
      unansweredAddressesProvider,
      (previous, next) => UnansweredAddresses.update(next),
    );

    // No DynamicColorBuilder: the palette is fixed on purpose so per-service
    // accents stay recognisable and the experience is identical on every OS.
    // See AppTheme.darkTheme.
    return MaterialApp.router(
      title: kAppName,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Leading is tightened at the top of the ramp (the display roles sit at
      // 1.0) and opened at the bottom (body at 22 on 15). Both ends need this,
      // in opposite directions, and one behaviour covers them:
      //
      // - A line box shorter than the glyph's ink lets the ink escape it. The
      //   display face needs its full 1.20em (Onest 1.275em) to contain an
      //   accented capital, so at 1.0 the acute on `Ý` pokes out the top, and
      //   media titles arrive from TMDB in every language. Inside anything that
      //   clips (the detail hero clips by design) that is a shaved accent.
      // - Extra leading below the last line is padding nobody asked for, and it
      //   would push every fixed-height box in the app out by a couple of
      //   points, since those constants encode a measured single line.
      //
      // Declining to apply the height to the block's outer ascent and descent
      // fixes both: the *gaps between* lines carry the leading decision, while
      // the block's edges keep the font's natural metrics. Prose gets its air,
      // display type stays tight, single-line chrome measures exactly what it
      // measured before, and nothing clips.
      //
      // Around all of it, the live region `announce()` speaks through where
      // the engine has no announcement channel (Android): one, above every
      // route, so a TalkBack user hears what a VoiceOver user hears. The
      // system bars in the room's ink (`ThemedSystemBars`). And Android's back
      // claimed for Settings, above every navigator (`SettingsBackClaim`).
      builder: (context, child) => ThemedSystemBars(
        child: AnnouncementHost(
          child: SettingsBackClaim(
            child: DefaultTextHeightBehavior(
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
