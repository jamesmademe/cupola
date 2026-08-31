import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/release_search/data/release_search_bootstrap.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerBundledFontLicense();
  final prefs = await SharedPreferences.getInstance();
  final secureSettingsStore = createSecureSettingsStore();
  final settingsService = SettingsService(prefs, secureSettingsStore);

  // Unconditional, including for a user who has background search switched
  // off — it is also what purges the records the last session left behind. See
  // its own doc.
  await configureBackgroundSearch();

  await settingsService.migrateFromPlaintext();
  final initialSettings = await _loadInitialSettings(settingsService);
  final onboardingCompleted = await settingsService.loadOnboardingComplete();

  runApp(
    ProviderScope(
      overrides: _buildProviderOverrides(
        prefs: prefs,
        secureSettingsStore: secureSettingsStore,
        initialSettings: initialSettings,
        activeInstances: settingsService.loadActiveInstances(),
        onboardingCompleted: onboardingCompleted,
      ),
      child: const CupolaApp(),
    ),
  );
}

/// Puts Inter's SIL OFL 1.1 into the licence page Flutter builds from
/// [LicenseRegistry].
///
/// The registry only knows about licences declared in package metadata, and a
/// font dropped into `assets/` has none — so the one obligation the OFL puts on
/// a binary that bundles the font, that its licence travel with it, would go
/// unmet in every shipped build. Registered before `runApp` because the
/// registry is read lazily and the callback must already be there when the
/// licence page asks.
void _registerBundledFontLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'Inter',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
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
}) {
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    secureSettingsStoreProvider.overrideWithValue(secureSettingsStore),
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

    // Keeps `CertTrustRegistry` in sync for the leaf image widgets that
    // cannot watch a provider themselves — see its doc for why. The `read`
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

    // No DynamicColorBuilder: the palette is fixed on purpose so per-service
    // accents stay recognisable and the experience is identical on every OS.
    // See AppTheme.darkTheme.
    return MaterialApp.router(
      title: 'Cupola',
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Leading is tightened at the top of the ramp (displayLarge sits at 1.06)
      // and opened at the bottom (bodyLarge at 1.55). Both ends need this, in
      // opposite directions, and one behaviour covers them:
      //
      // - A line box shorter than the glyph's ink lets the ink escape it. Inter
      //   needs its full 1.21em to contain an accented capital, so at 1.06 the
      //   acute on `Ý` pokes out the top — and media titles arrive from TMDB in
      //   every language. Inside anything that clips (the detail hero clips by
      //   design) that is a shaved accent.
      // - Extra leading below the last line is padding nobody asked for, and it
      //   would have pushed every fixed-height box in the app out by a couple of
      //   points, since those constants encode a measured line at the old 1.21.
      //
      // Declining to apply the height to the block's outer ascent and descent
      // fixes both: the *gaps between* lines carry the leading decision, while
      // the block's edges keep the font's natural metrics. Prose gets its air,
      // display type stays tight, single-line chrome measures exactly what it
      // measured before, and nothing clips.
      builder: (context, child) => DefaultTextHeightBehavior(
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
