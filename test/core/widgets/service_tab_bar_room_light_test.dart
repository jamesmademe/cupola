import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/qbittorrent_actions_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// WCAG contrast of two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

final _themes = {'dark': AppTheme.darkTheme(), 'light': AppTheme.lightTheme()};

final _tabbed = [
  for (final s in ServiceKey.values)
    if (tabsFor(s) != null) s,
];

/// Two Radarr connections, so the lens draws.
const _twoRadarrs = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'https://four-k.lan:7878',
      credential: 'k',
    ),
    ServiceInstance(
      id: 'radarr-hd11111',
      service: ServiceKey.radarr,
      label: 'HD',
      url: 'https://hd.lan:7879',
      credential: 'k',
    ),
  ],
);

const _bandKey = ValueKey('service-header-band');
const _bloomKey = ValueKey('service-header-bloom');

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  required ServiceKey service,
  bool header = true,
  ServiceTab? current,
  bool withLens = false,
  List<Widget> actions = const [],
}) async {
  tester.view.physicalSize = const Size(1440, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tab = current ?? tabsFor(service)!.first;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => withLens ? _twoRadarrs : const SettingsModel(),
        ),
        initialActiveInstancesProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: header
                ? ServiceTabBar.header(
                    service: service,
                    current: tab,
                    onSelected: (_) {},
                    lens: withLens ? InstanceLensBadge(service: service) : null,
                    actions: actions,
                  )
                : ServiceTabBar(
                    service: service,
                    current: tab,
                    onSelected: (_) {},
                  ),
          ),
        ),
      ),
    ),
  );
}

Finder _inBar(Finder matching) =>
    find.descendant(of: find.byType(ServiceTabBar), matching: matching);

void main() {
  group('ServiceTabBar.header is lit by the lamp', () {
    for (final MapEntry(key: themeName, value: theme) in _themes.entries) {
      for (final service in [ServiceKey.radarr, ServiceKey.sonarr]) {
        testWidgets('${service.name}, $themeName: the band is the lamp at '
            '0.12 over the surface, with a bloom at its foot', (tester) async {
          // A service room has no artwork, so it is lit by the neutral lamp;
          // the same light for every service, never the service's colour.
          expect(service.accent, AppColors.lamp);
          await _pump(tester, theme: theme, service: service);

          final band = tester.widget<ColoredBox>(
            find
                .descendant(
                  of: find.byKey(_bandKey),
                  matching: find.byType(ColoredBox),
                )
                .first,
          );
          expect(
            band.color,
            Color.alphaBlend(
              service.accent.withValues(alpha: 0.12),
              theme.colorScheme.surface,
            ),
          );
          expect(band.color.a, 1.0, reason: 'opaque, not glass');

          final bloom = tester.widget<DecoratedBox>(find.byKey(_bloomKey));
          final gradient =
              (bloom.decoration as BoxDecoration).gradient! as LinearGradient;
          expect(gradient.begin, Alignment.topCenter);
          expect(gradient.end, Alignment.bottomCenter);
          expect(gradient.colors, [
            service.accent.withValues(alpha: 0),
            service.accent.withValues(alpha: ServiceTabBar.bloomAlpha),
          ]);

          // Confined to the band's lower 11px, across its full width.
          final bandRect = tester.getRect(find.byKey(_bandKey));
          final bloomRect = tester.getRect(find.byKey(_bloomKey));
          expect(bloomRect.height, 11);
          expect(bloomRect.bottom, bandRect.bottom);
          expect(bloomRect.width, bandRect.width);
        });
      }
    }

    testWidgets('the bloom is painted under the tabs', (tester) async {
      await _pump(
        tester,
        theme: AppTheme.darkTheme(),
        service: ServiceKey.radarr,
      );
      // Earlier in the band's Stack is lower in paint order: the tabs are
      // drawn over the bloom, not under it.
      final stack = tester.widget<Stack>(
        find
            .descendant(of: find.byKey(_bandKey), matching: find.byType(Stack))
            .first,
      );
      final bloomIndex = stack.children.indexWhere(
        (child) => find
            .descendant(
              of: find.byWidget(child),
              matching: find.byKey(_bloomKey),
            )
            .evaluate()
            .isNotEmpty,
      );
      final tabsIndex = stack.children.indexWhere(
        (child) => find
            .descendant(
              of: find.byWidget(child),
              matching: find.byType(SingleChildScrollView),
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(bloomIndex, 0);
      expect(tabsIndex, greaterThan(bloomIndex));
    });

    testWidgets('no text is drawn over the bloom', (tester) async {
      await _pump(
        tester,
        theme: AppTheme.darkTheme(),
        service: ServiceKey.radarr,
        withLens: true,
      );
      final bandRect = tester.getRect(find.byKey(_bandKey));
      final texts = _inBar(find.byType(Text));
      expect(texts, findsWidgets);
      for (final element in texts.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(
          rect.bottom,
          lessThanOrEqualTo(bandRect.bottom - ServiceTabBar.bloomHeight),
          reason: (element.widget as Text).data,
        );
      }
    });

    testWidgets('no second selection: nothing on the band draws a 2px line', (
      tester,
    ) async {
      // The selected tab's pill is the band's one mark of selection. A 2px
      // border along the band would read as a second one.
      await _pump(
        tester,
        theme: AppTheme.darkTheme(),
        service: ServiceKey.radarr,
      );
      final decorations = <BoxDecoration>[
        for (final w in tester.widgetList<DecoratedBox>(
          _inBar(find.byType(DecoratedBox)),
        ))
          if (w.decoration case final BoxDecoration d) d,
      ];
      expect(decorations, isNotEmpty);
      for (final d in decorations) {
        if (d.border case final Border border) {
          for (final side in [border.top, border.bottom]) {
            expect(side.width, lessThan(2), reason: '$d');
          }
        }
      }
    });

    for (final MapEntry(key: themeName, value: theme) in _themes.entries) {
      testWidgets('$themeName: every label clears 4.5:1 on the lit band, for '
          'every tabbed service', (tester) async {
        for (final service in _tabbed) {
          final tabs = tabsFor(service)!;
          // A selected tab that is not the first, so the row carries both a
          // selected and an unselected label.
          await _pump(
            tester,
            theme: theme,
            service: service,
            current: tabs.length > 1 ? tabs[1] : tabs.first,
          );
          final surface = ServiceTabBar.headerSurfaceOf(
            theme.colorScheme,
            service,
          );

          final texts = tester.widgetList<Text>(_inBar(find.byType(Text)));
          // Every tab plus the service's name.
          expect(texts.length, tabs.length + 1, reason: service.name);
          for (final text in texts) {
            final ink = text.style!.color!;
            expect(ink.a, 1.0, reason: '${service.name} ${text.data}');
            expect(
              _contrast(ink, surface),
              greaterThanOrEqualTo(4.5),
              reason: '${service.name} "${text.data}"',
            );
          }
        }
      });

      testWidgets('$themeName: the selected tab is the strong-fill pill under '
          'the primary ink, for every tabbed service', (tester) async {
        // The brand book: never the service's colour. The pill of the phone's bar and the
        // desktop rail, on every service. It replaced a 2px rule in the
        // service's accent, which had to be solved against the bloom under it.
        for (final service in _tabbed) {
          await _pump(tester, theme: theme, service: service);
          final pills = tester.widgetList<Container>(
            _inBar(find.byKey(const ValueKey('service-tab-pill'))),
          );
          expect(pills, hasLength(1), reason: service.name);
          final fill = (pills.single.decoration! as BoxDecoration).color!;
          expect(fill, CupolaRoom.forBrightness(theme.brightness).fillStrong);
          final selected = tester.widget<Text>(
            find.text(tabsFor(service)!.first.label),
          );
          expect(selected.style!.color, theme.colorScheme.onSurface);
          final surface = ServiceTabBar.headerSurfaceOf(
            theme.colorScheme,
            service,
          );
          expect(
            _contrast(selected.style!.color!, Color.alphaBlend(fill, surface)),
            greaterThanOrEqualTo(4.5),
            reason: service.name,
          );
        }
      });

      testWidgets('$themeName: the lens and the action are walked against the '
          'lit band', (tester) async {
        await _pump(
          tester,
          theme: theme,
          service: ServiceKey.radarr,
          withLens: true,
        );
        final lensLabel = tester.widget<Text>(
          find.descendant(
            of: find.byType(InstanceLensBadge),
            matching: find.byType(Text),
          ),
        );
        // The pill is the service's accent, the lamp, at 0.15 over the band.
        final pill = Color.alphaBlend(
          ServiceKey.radarr.accent.withValues(alpha: 0.15),
          ServiceTabBar.headerSurfaceOf(theme.colorScheme, ServiceKey.radarr),
        );
        expect(
          _contrast(lensLabel.style!.color!, pill),
          greaterThanOrEqualTo(4.5),
        );

        await _pump(
          tester,
          theme: theme,
          service: ServiceKey.qbittorrent,
          actions: const [QbittorrentActionsBar()],
        );
        final qbSurface = ServiceTabBar.headerSurfaceOf(
          theme.colorScheme,
          ServiceKey.qbittorrent,
        );
        final glyphs = tester.widgetList<Icon>(
          find.descendant(
            of: find.byType(QbittorrentActionsBar),
            matching: find.byType(Icon),
          ),
        );
        expect(glyphs, isNotEmpty);
        for (final glyph in glyphs) {
          expect(
            _contrast(glyph.color!, qbSurface),
            greaterThanOrEqualTo(4.5),
            reason: '${glyph.icon}',
          );
        }
      });

      testWidgets('$themeName: the phone bar is unlit: no band, no bloom, '
          'and its selected label the primary ink', (tester) async {
        await _pump(
          tester,
          theme: theme,
          service: ServiceKey.radarr,
          header: false,
        );

        expect(find.byKey(_bandKey), findsNothing);
        expect(find.byKey(_bloomKey), findsNothing);
        expect(find.byType(ServiceBandSurface), findsNothing);
        expect(_inBar(find.byType(ColoredBox)), findsNothing);
        final selected = tester.widget<Text>(
          find.text(ServiceTab.overview.label),
        );
        expect(selected.style!.color, theme.colorScheme.onSurface);
      });
    }
  });
}
