/// The design catalog: every documented widget, rendered by the real widget.
///
/// Each `*_catalog_test.dart` beside this file declares one card of the design
/// system (`design/system/components/<Card>/README.md`) as a list of scenes and
/// hands it to [catalogCard]. Running
///
///     flutter test --tags catalog --run-skipped
///
/// writes `build/design_catalog/<Card>/<platform>.<theme>.png` — one sheet per
/// platform the scenes ask for, in dark and light, at twice logical size. The
/// catalog asserts nothing: its job is to show what the code draws, so that a
/// reader never has to trust a re-drawing of it. Its one guarantee is that it
/// compiles, which is what makes a renamed parameter or a dropped variant fail
/// loudly instead of leaving a stale picture behind. One thing it does report:
/// a scene that overflows is drawn anyway, with Flutter's stripe over the
/// overflow, and the line that says by how much and where lands in
/// `<platform>.<theme>.findings.txt` beside the sheet and in the test output
/// (`catalog finding · …`), so a size that breaks a widget is read, not buried.
///
/// Every card is drawn at the default reading size and, in at least one scene,
/// at twice it (`CatalogScene.textScale`); the guard beside this file holds that.
///
/// Rendering is deterministic on one machine (byte-identical across runs) but
/// not across hosts, which is why the images are built, not committed.
///
/// What a sheet cannot show, and how the cards deal with it:
/// - a modal opened on the root navigator — open it on a scene-local
///   `Navigator`, or draw its public parts; otherwise the README describes it;
/// - hover, and any other pointer-only state;
/// - a frame in the middle of a motion — the sheet is pumped in 400ms steps,
///   so it lands before or after; motion has its own cards in
///   `design/system/motion/`;
/// - a provider that arms a timer (a reachability probe, a poll) — override it
///   with a settled or never-completing future, or the pending timer fails the
///   test.
library;

import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client;

import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';

/// Where the sheets land. `build/` is ignored, and the catalog is rebuilt, not
/// kept.
const catalogOutput = 'build/design_catalog';

/// The platforms a sheet can be drawn for. The platform is global to a render
/// — it decides visual density, the padded tap target and the desktop shell —
/// so scenes that differ in platform land on different sheets.
enum CatalogPlatform {
  /// iOS: the phone the app is used on most. Padded 48dp tap targets,
  /// standard density.
  phone(TargetPlatform.iOS),

  /// macOS: the desktop shell. Compact density, shrink-wrapped targets.
  desktop(TargetPlatform.macOS);

  const CatalogPlatform(this.target);
  final TargetPlatform target;
}

/// One state of a widget, drawn with its caption underneath.
class CatalogScene {
  const CatalogScene(
    this.caption,
    this.build, {
    this.width,
    this.height,
    this.platform = CatalogPlatform.phone,
    this.overrides = const [],
    this.textScale = 1,
  });

  /// What the scene shows — the constructor or variant, and the state. Written
  /// for a reader who has the README beside it.
  final String caption;

  final WidgetBuilder build;

  /// The box the scene is laid out in. When [width] is given the scene also
  /// sees a `MediaQuery` of that size, so breakpoint-driven layouts draw the
  /// form they take at that width; leave it null for a free-standing control.
  final double? width;
  final double? height;

  final CatalogPlatform platform;

  /// Provider overrides for this scene alone. A scene that has any gets a
  /// container of its own, built from the card's overrides and then these, so
  /// providers derived from an overridden one see the override too — a nested
  /// `ProviderScope` would replace only the providers it names.
  final List<Override> overrides;

  /// The reading size the scene is drawn at: the system's text scale, as a
  /// person who raised it in Settings has it. 1 is the default size; 2 is the
  /// largest size the catalog holds every card to ([catalogTextScale]).
  final double textScale;
}

/// The reading size every card has to be seen at at least once: twice the
/// default. A label that fits at 1 and clips, overflows or collides at 2 is
/// the commonest defect a resting-state sheet hides, so each card declares a
/// scene with `textScale: catalogTextScale` and
/// `test/design_catalog/catalog_scenes_guard_test.dart` fails when one does
/// not.
const catalogTextScale = 2.0;

/// Artwork a scene can show. The URLs are served from
/// `design/system/assets/Imagery/` through the app's own image cache seam, so
/// a widget that loads a poster over the network draws the sample poster.
abstract final class CatalogArt {
  static const poster = 'https://art.catalog/poster.jpg';
  static const backdrop = 'https://art.catalog/backdrop.jpg';

  static const _files = {
    poster: 'design/system/assets/Imagery/poster.jpg',
    backdrop: 'design/system/assets/Imagery/backdrop.jpg',
  };

  /// The same pictures as a Seerr record links them: TMDB paths, which the
  /// app turns into TMDB addresses of any size.
  static const tmdbPoster = '/catalog-poster.jpg';
  static const tmdbBackdrop = '/catalog-backdrop.jpg';

  /// The file behind [url]: a catalog address, or a TMDB address of one of
  /// the catalog's paths at any size.
  static String? _fileFor(String url) =>
      _files[url] ??
      switch (Uri.tryParse(url)) {
        Uri(host: 'image.tmdb.org', :final path)
            when path.endsWith(tmdbPoster) =>
          _files[poster],
        Uri(host: 'image.tmdb.org', :final path)
            when path.endsWith(tmdbBackdrop) =>
          _files[backdrop],
        _ => null,
      };

  static final _images = <String, MemoryImage>{};

  /// The same artwork as an [ImageProvider], for widgets that take one.
  /// Decoded before the sheet is drawn, so it paints on the first frame.
  static ImageProvider get posterImage => _images[poster]!;
  static ImageProvider get backdropImage => _images[backdrop]!;

  static void _read() {
    for (final MapEntry(key: url, value: path) in _files.entries) {
      _images[url] ??= MemoryImage(io.File(path).readAsBytesSync());
    }
  }
}

/// Serves [CatalogArt] URLs from disk. Stands in for a real [CacheManager],
/// which opens a sqflite store and cannot be built in a widget test.
class _ArtCacheManager implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final path = CatalogArt._fileFor(url);
    if (path == null) throw StateError('no catalog artwork at $url');
    yield FileInfo(
      const LocalFileSystem().file(path),
      FileSource.Cache,
      DateTime(2100),
      url,
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _NoTransport implements Client {
  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

Future<void> _loadFonts() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  await _loadMonoFaces();
}

/// Every family ends its fallbacks on platform faces the app does not bundle —
/// Apple Symbols for the modifier glyphs (⌘ ⌥) no bundled face has, then the
/// mono faces — so a widget test would draw those glyphs as boxes. On a Mac
/// the sheet borrows the system's: Apple Symbols under its own name and under
/// `SF Mono`, SF Mono under `Menlo`. Elsewhere the faces are simply missing.
Future<void> _loadMonoFaces() async {
  const faces = {
    'Apple Symbols': '/System/Library/Fonts/Apple Symbols.ttf',
    'Menlo': '/System/Library/Fonts/SFNSMono.ttf',
    'SF Mono': '/System/Library/Fonts/Apple Symbols.ttf',
  };
  for (final MapEntry(key: family, value: path) in faces.entries) {
    final file = io.File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

/// Declares one card: a test per platform its scenes use, each writing a dark
/// and a light sheet.
///
/// [overrides] builds the provider overrides every scene shares — typically
/// `settingsScopeOverrides(...)` from `test_helpers`. [width] is the sheet's
/// logical width; scenes wider than it minus the 24pt margin are clipped.
void catalogCard(
  String card, {
  required List<CatalogScene> scenes,
  Future<List<Override>> Function()? overrides,
  double width = 960,
}) {
  setUpAll(() async {
    await _loadFonts();
    CatalogArt._read();
  });

  for (final platform in CatalogPlatform.values) {
    final group = [
      for (final scene in scenes)
        if (scene.platform == platform) scene,
    ];
    if (group.isEmpty) continue;

    testWidgets('$card · ${platform.name}', (tester) async {
      CertTrustRegistry.update(const {
        'https://art.catalog:443': 'catalog',
        'https://image.tmdb.org:443': 'catalog',
      });
      pinnedImageCacheBuilder =
          ({
            required cacheKey,
            required fingerprint,
            required host,
            required port,
          }) => (manager: _ArtCacheManager(), transport: _NoTransport());
      addTearDown(() {
        resetPinnedImageCaches();
        pinnedImageCacheBuilder = defaultPinnedImageCacheBuilder;
        CertTrustRegistry.reset();
      });

      final shared = await overrides?.call() ?? const <Override>[];
      debugDefaultTargetPlatformOverride = platform.target;
      try {
        // Built after the override: ThemeData reads the platform for its
        // density and tap-target size when it is constructed.
        final themes = {
          'dark': AppTheme.darkTheme(),
          'light': AppTheme.lightTheme(),
        };
        for (final MapEntry(key: name, value: theme) in themes.entries) {
          await _render(tester, card, platform, name, theme, width, group, [
            ...shared,
          ]);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Future<void> _render(
  WidgetTester tester,
  String card,
  CatalogPlatform platform,
  String themeName,
  ThemeData theme,
  double width,
  List<CatalogScene> scenes,
  List<Override> overrides,
) async {
  // flutter_test paints every shadow as a hard, unblurred slab so goldens stay
  // stable across hosts. The catalog wants the shadows the app paints, and has
  // to hand the flag back before the test body ends: the painting invariants
  // are checked before any tear-down runs.
  debugDisableShadows = false;
  // A scene that overflows is a finding, not a failure: the sheet still draws
  // (with Flutter's yellow and black stripe over the overflow), and the line is
  // written beside it. Any other error is the test's to fail.
  final findings = <String>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final finding = _overflowFinding(details);
    if (finding == null) {
      previousOnError?.call(details);
    } else if (!findings.contains(finding)) {
      findings.add(finding);
    }
  };
  try {
    await _paint(
      tester,
      card,
      platform,
      themeName,
      theme,
      width,
      scenes,
      overrides,
    );
  } finally {
    FlutterError.onError = previousOnError;
    debugDisableShadows = true;
  }
  final file = io.File(
    '$catalogOutput/$card/${platform.name}.$themeName.findings.txt',
  );
  if (findings.isEmpty) {
    if (file.existsSync()) file.deleteSync();
    return;
  }
  file.writeAsStringSync('${findings.join('\n')}\n');
  for (final finding in findings) {
    debugPrint(
      'catalog finding · $card · ${platform.name}.$themeName · $finding',
    );
  }
}

/// The one-line account of a RenderFlex overflow ("A RenderFlex overflowed by
/// 24 pixels on the right · lib/core/widgets/tag_chip.dart:56"), the widget at
/// fault and the line that built it, or null for any other error.
String? _overflowFinding(FlutterErrorDetails details) {
  if (!details.exceptionAsString().contains('overflowed by')) return null;
  // The whole report, not the message alone: the widget at fault and the line
  // that built it are in the diagnostics that follow the message.
  final report = details.toString();
  final message = report
      .split('\n')
      .firstWhere((l) => l.contains('overflowed by'), orElse: () => 'overflow');
  final where = RegExp(
    r'error-causing widget[^\n]*\n[^\n]*\n\s*\S+:file://\S*?/((?:lib|test)/[^:\s]+:\d+)',
  ).firstMatch(report)?.group(1);
  return where == null ? message : '$message · $where';
}

Future<void> _paint(
  WidgetTester tester,
  String card,
  CatalogPlatform platform,
  String themeName,
  ThemeData theme,
  double width,
  List<CatalogScene> scenes,
  List<Override> overrides,
) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const sheet = ValueKey('catalog-sheet');

  // Decode the artwork first: an image that resolves inside the fake-async
  // zone of a widget test never completes.
  await tester.pumpWidget(const SizedBox());
  final context = tester.element(find.byType(SizedBox));
  await tester.runAsync(() async {
    for (final image in CatalogArt._images.values) {
      await precacheImage(image, context);
    }
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        // The app root's text height behaviour, or every measured line differs.
        builder: (context, child) => DefaultTextHeightBehavior(
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
          child: child!,
        ),
        home: Material(
          color: Colors.transparent,
          // As tall as its scenes: a card with many of them outgrows the
          // window, and a sheet cut at the window's height would lose its
          // last scenes without a word.
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxHeight: double.infinity,
            child: RepaintBoundary(
              key: sheet,
              child: _Sheet(width: width, scenes: scenes, shared: overrides),
            ),
          ),
        ),
      ),
    ),
  );

  // No pumpAndSettle: spinners and shimmers never settle. Pump a fixed stretch
  // of time instead, with real time in between so artwork read from disk
  // decodes.
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(sheet),
    );
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    io.File('$catalogOutput/$card/${platform.name}.$themeName.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.width,
    required this.scenes,
    required this.shared,
  });

  final double width;
  final List<Override> shared;
  final List<CatalogScene> scenes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final caption = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final media = MediaQuery.of(context);

    return Container(
      width: width,
      color: scheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final scene in scenes) ...[
            _SceneScope(
              overrides: scene.overrides.isEmpty
                  ? const []
                  : [...shared, ...scene.overrides],
              child: ClipRect(
                clipper: const _SceneClip(),
                child: SizedBox(
                  width: scene.width,
                  height: scene.height,
                  child: scene.width == null && scene.textScale == 1
                      ? Builder(builder: scene.build)
                      : MediaQuery(
                          data: media.copyWith(
                            size: scene.width == null
                                ? media.size
                                : Size(
                                    scene.width!,
                                    scene.height ?? media.size.height,
                                  ),
                            textScaler: scene.textScale == 1
                                ? media.textScaler
                                : TextScaler.linear(scene.textScale),
                          ),
                          child: Builder(builder: scene.build),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(scene.caption, style: caption),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

/// Keeps what a scene paints out of its neighbours: Flutter's overflow marker
/// is a bar about 230pt tall that would draw across the scenes above and below
/// the one that overflows. Shadows and glows still bleed 40pt past the box, and
/// anything may run out to the right.
class _SceneClip extends CustomClipper<Rect> {
  const _SceneClip();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-24, -40, size.width + 2000, size.height + 40);

  @override
  bool shouldReclip(_SceneClip oldClipper) => false;
}

/// A scene's own provider container, when it overrides anything; retries are
/// off, since a sheet is drawn once and a retry timer would outlive the test.
class _SceneScope extends StatefulWidget {
  const _SceneScope({required this.overrides, required this.child});

  final List<Override> overrides;
  final Widget child;

  @override
  State<_SceneScope> createState() => _SceneScopeState();
}

class _SceneScopeState extends State<_SceneScope> {
  late final ProviderContainer? _container = widget.overrides.isEmpty
      ? null
      : ProviderContainer(
          overrides: widget.overrides,
          retry: (retryCount, error) => null,
        );

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final container = _container;
    return container == null
        ? widget.child
        : UncontrolledProviderScope(container: container, child: widget.child);
  }
}
