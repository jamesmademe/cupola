// GENERATED — edit design/tokens/, then run `dart run tool/design_tokens/generate.dart`.
//
// Never edit this file by hand: the test suite regenerates it from the token
// sets and fails on any difference.

import 'dart:ui' show Color, FontWeight;

/// The design tokens every theme shares, from `design/tokens/core.json`.
abstract final class DesignTokens {
  // color.base
  /// Pure white: reversed-out labels on the brand and on deep status fills.
  static const Color colorBaseWhite = Color(0xFFFFFFFF);

  /// Pure black: modal scrims, the dark theme's shadow ink and the glass
  /// shadow.
  static const Color colorBaseBlack = Color(0xFF000000);

  // color.brand
  /// Indigo Deep (indigo-600), fixed in both themes. The light theme's primary,
  /// and the dark theme's primary container.
  static const Color colorBrandPrimaryDark = Color(0xFF4F46E5);

  /// Indigo Light (indigo-400), fixed. The dark theme's secondary and the light
  /// theme's inverse primary.
  static const Color colorBrandPrimaryLight = Color(0xFF818CF8);

  /// Indigo Pale (indigo-300), fixed. Text on the dark primary container; the
  /// light primary container.
  static const Color colorBrandPrimaryLighter = Color(0xFFA5B4FC);

  // color.service
  /// Seerr Indigo (indigo-500): the Seerr accent and the app's own brand
  /// colour, the dark theme's primary.
  static const Color colorServiceSeerr = Color(0xFF6366F1);

  /// Radarr Amber, the movies accent. A fill label on it takes ink-on-bright:
  /// white measures 2.15:1.
  static const Color colorServiceRadarr = Color(0xFFF59E0B);

  /// Sonarr Violet, the series accent; also the brand gradient's end.
  static const Color colorServiceSonarr = Color(0xFF8B5CF6);

  /// Lidarr Pink, the music accent.
  static const Color colorServiceLidarr = Color(0xFFEC4899);

  /// Readarr Red, the books accent.
  static const Color colorServiceReadarr = Color(0xFFC0392B);

  /// Prowlarr Orange, the indexers accent.
  static const Color colorServiceProwlarr = Color(0xFFE66000);

  /// Bazarr Sky, the subtitles accent.
  static const Color colorServiceBazarr = Color(0xFF25A7DF);

  /// qBittorrent Blue, the torrent client accent.
  static const Color colorServiceQbittorrent = Color(0xFF2F67BA);

  /// Transmission Crimson: walked off the brand red so it clears readarr (ΔE
  /// 10.8) and the error tone (ΔE 8.8).
  static const Color colorServiceTransmission = Color(0xFFE11D48);

  /// SABnzbd Gold, a usenet client accent.
  static const Color colorServiceSabnzbd = Color(0xFFF0A800);

  /// NZBGet Green, a usenet client accent.
  static const Color colorServiceNzbget = Color(0xFF0F9D58);

  /// Dockge Teal, the stacks accent.
  static const Color colorServiceDockge = Color(0xFF058373);

  /// TrueNAS Blue, the storage accent.
  static const Color colorServiceTruenas = Color(0xFF0095D5);

  /// Unraid Orange, the server accent.
  static const Color colorServiceUnraid = Color(0xFFFF8C2B);

  /// Nginx Proxy Manager Vermilion, the brand value unchanged: a red-orange
  /// clear of the amber band.
  static const Color colorServiceNginxProxyManager = Color(0xFFF15833);

  /// Jellyfin Purple, a streaming accent.
  static const Color colorServiceJellyfin = Color(0xFFAA5CC3);

  /// Plex Bronze: deliberately not brand gold #E5A00D, which collides with
  /// sabnzbd and the fault tone.
  static const Color colorServicePlex = Color(0xFFC97A16);

  // color.nav
  /// Dashboard tab pill: the app's own indigo.
  static const Color colorNavDashboard = colorServiceSeerr;

  /// Section Cyan (cyan-500), the Activity tab pill. A section, not a service,
  /// and never a status hue.
  static const Color colorNavActivity = Color(0xFF06B6D4);

  /// Section Purple (purple-500), the Search tab pill.
  static const Color colorNavSearch = Color(0xFFA855F7);

  /// Section Teal (teal-500), the Settings tab pill.
  static const Color colorNavSettings = Color(0xFF14B8A6);

  // color.status
  /// GREEN (green-500): available or complete. A fill byte; as text it always
  /// goes through the tone walk.
  static const Color colorStatusSuccess = Color(0xFF22C55E);

  /// Deep green (green-800): the dark success container, and text on the light
  /// one.
  static const Color colorStatusSuccessContainer = Color(0xFF166534);

  /// AMBER (yellow-400): a fault, never the backlog. Deliberately not radarr's
  /// amber-500.
  static const Color colorStatusWarning = Color(0xFFFACC15);

  /// RED (red-500): unreachable, and nothing else.
  static const Color colorStatusError = Color(0xFFEF4444);

  /// Deep red (red-800): the dark error container, and text on the light one.
  static const Color colorStatusErrorContainer = Color(0xFF991B1B);

  /// BLUE (blue-500): queued or informational.
  static const Color colorStatusInfo = Color(0xFF3B82F6);

  // color
  /// gray-900: the label a bright fill takes where white loses the contrast
  /// measurement.
  static const Color colorInkOnBright = Color(0xFF111827);

  // color.plate
  /// Artwork stand-in (a missing poster, an album without cover). Fixed dark in
  /// both themes: artwork is not palette.
  static const Color colorPlateSurface = Color(0xFF1E2430);

  /// The letterboxed well behind a backdrop; fixed dark in both themes.
  static const Color colorPlateWell = Color(0xFF08090F);

  /// Hairline on a plate; fixed.
  static const Color colorPlateOutline = Color(0xFF2D3748);

  /// Primary text on a plate.
  static const Color colorPlateInk = Color(0xFFF0F2F8);

  /// Secondary text on a plate: 5.49:1 on the plate surface, 7.02:1 on the
  /// well.
  static const Color colorPlateDimInk = Color(0xFF909AAD);

  // space
  /// Inside components only: glyph-to-label gap, between two lines of a row.
  static const double spaceXxs = 2;

  /// Minimal spacing for tight layouts; chip vertical padding.
  static const double spaceXs = 4;

  /// Inside components only: chip inner padding, nav bar inner padding.
  static const double spaceS = 6;

  /// Small spacing for related elements; badge padding.
  static const double spaceSm = 8;

  /// Inside components only: row line gaps, inner plates.
  static const double spaceM = 10;

  /// Compact spacing: grid and carousel gaps, button vertical padding.
  static const double spaceMd = 12;

  /// Inside components only: nav pill horizontal padding.
  static const double spaceMl = 14;

  /// The default: page gutter, card padding, input horizontal padding.
  static const double spaceLg = 16;

  /// Section separation; button horizontal padding.
  static const double spaceXl = 24;

  /// Major blocks.
  static const double spaceXxl = 32;

  /// The largest section break.
  static const double spaceXxxl = 48;

  /// Gap between grid items.
  static const double spaceGridGap = spaceMd;

  /// Gap between carousel items.
  static const double spaceCarouselGap = spaceMd;

  // radius
  /// Sharp corners (full-bleed backdrops).
  static const double radiusNone = 0;

  /// Small-object geometry: a 3dp tag.
  static const double radiusHair = 3;

  /// Subtle curves; progress tracks.
  static const double radiusXs = 4;

  /// Small-object geometry: a poster corner in dense rails.
  static const double radiusXs2 = 6;

  /// Chips, badges and small objects.
  static const double radiusSm = 8;

  /// Small-object geometry: an inner plate.
  static const double radiusSm2 = 10;

  /// The default: cards, buttons, inputs, posters, snackbars, list tiles.
  static const double radiusMd = 12;

  /// Dialogs, bottom-sheet top corners, grouped settings.
  static const double radiusLg = 16;

  /// Selected affordances only: the nav indicator and segment pills. Never a
  /// general corner.
  static const double radiusPill = 20;

  /// The floating navigation bar.
  static const double radiusXl = 28;

  /// Metadata pills (tags, genres, ratings). Never an interactive container.
  static const double radiusFull = 50;

  // breakpoint
  /// Below this width the floating bar switches to compact item targets.
  static const double breakpointNavCompact = 360;

  /// Below this width a desktop window paints the touch shell under a bare drag
  /// strip.
  static const double breakpointDesktopMobile = 720;

  /// At or above this width a touch build moves from the bottom bar to a side
  /// rail.
  static const double breakpointTouchRail = 840;

  /// Below this width the desktop shell uses its compact variants.
  static const double breakpointDesktopCompact = 1100;

  /// The widest the main content well may grow, on any shell.
  static const double breakpointContentWell = 1140;

  /// Narrowest a desktop window may be dragged: a small phone's width.
  static const double breakpointDesktopMinWidth = 360;

  /// Shortest a desktop window may be dragged: the compact artboard's height.
  static const double breakpointDesktopMinHeight = 450;

  /// Aspect ratio at or above which a frame puts two things side by side
  /// instead of stacking. A shape, not a width.
  static const double breakpointLandscapeAspect = 1.2;

  // duration
  /// Micro-interactions: ripples, highlights.
  static const Duration durationXs = Duration(milliseconds: 100);

  /// Simple state changes.
  static const Duration durationSm = Duration(milliseconds: 200);

  /// Standard transitions.
  static const Duration durationMd = Duration(milliseconds: 300);

  /// Complex transitions.
  static const Duration durationLg = Duration(milliseconds: 400);

  /// Dramatic effects.
  static const Duration durationXl = Duration(milliseconds: 500);

  /// One skeleton shimmer cycle.
  static const Duration durationShimmer = Duration(milliseconds: 1500);

  /// How long a transient success check replaces a button's icon before
  /// reverting.
  static const Duration durationConfirmationHold = Duration(milliseconds: 1600);

  // opacity
  /// A service accent's soft container: icon backgrounds and chips.
  static const double opacityServiceSoftContainer = 0.14;

  /// Centre of a signature card's accent glow. A grid repeating the treatment
  /// takes a fraction of it.
  static const double opacityServiceGlow = 0.22;

  /// Mid stop of the hero scrim at rest; it deepens to opaque as the hero
  /// collapses.
  static const double opacityHeroScrimRest = 0.85;

  /// Top stop of the hero scrim once collapsed, so the art recedes behind
  /// chrome.
  static const double opacityHeroScrimDeep = 0.35;

  /// The surface behind a status badge laid over artwork.
  static const double opacityStatusBadge = 0.8;

  // shadow.level-1.contact
  static const double shadowLevel1ContactOffsetX = 0;

  static const double shadowLevel1ContactOffsetY = 2;

  static const double shadowLevel1ContactBlur = 6;

  static const double shadowLevel1ContactSpread = 0;

  // shadow.level-1.ambient
  static const double shadowLevel1AmbientOffsetX = 0;

  static const double shadowLevel1AmbientOffsetY = 4;

  static const double shadowLevel1AmbientBlur = 12;

  static const double shadowLevel1AmbientSpread = 0;

  // shadow.level-2.contact
  static const double shadowLevel2ContactOffsetX = 0;

  static const double shadowLevel2ContactOffsetY = 4;

  static const double shadowLevel2ContactBlur = 10;

  static const double shadowLevel2ContactSpread = 0;

  // shadow.level-2.ambient
  static const double shadowLevel2AmbientOffsetX = 0;

  static const double shadowLevel2AmbientOffsetY = 10;

  static const double shadowLevel2AmbientBlur = 22;

  static const double shadowLevel2AmbientSpread = 0;

  // shadow.level-3.contact
  static const double shadowLevel3ContactOffsetX = 0;

  static const double shadowLevel3ContactOffsetY = 6;

  static const double shadowLevel3ContactBlur = 16;

  static const double shadowLevel3ContactSpread = 0;

  // shadow.level-3.ambient
  static const double shadowLevel3AmbientOffsetX = 0;

  static const double shadowLevel3AmbientOffsetY = 18;

  static const double shadowLevel3AmbientBlur = 36;

  static const double shadowLevel3AmbientSpread = 0;

  // shadow.glass.ambient
  static const Color shadowGlassAmbientColor = colorBaseBlack;

  static const double shadowGlassAmbientOffsetX = 0;

  static const double shadowGlassAmbientOffsetY = 8;

  static const double shadowGlassAmbientBlur = 32;

  static const double shadowGlassAmbientSpread = 0;

  // shadow.glass.highlight
  static const Color shadowGlassHighlightColor = colorBaseWhite;

  static const double shadowGlassHighlightOffsetX = 0;

  static const double shadowGlassHighlightOffsetY = 1;

  static const double shadowGlassHighlightBlur = 0;

  static const double shadowGlassHighlightSpread = 0;

  // type.family
  /// The bundled Inter variable font (wght 100–900, opsz 14–32). Every role is
  /// set in it.
  static const String typeFamilySans = 'Inter';
  static const List<String> typeFamilySansFallback = <String>[];

  /// Code, logs, hashes and anything compared by eye in columns, in resolution
  /// order. Never the bare 'monospace' alias, which Apple platforms do not
  /// have.
  static const String typeFamilyMono = 'Menlo';
  static const List<String> typeFamilyMonoFallback = <String>[
    'SF Mono',
    'Roboto Mono',
    'Droid Sans Mono',
    'Consolas',
    'monospace',
  ];

  // type.display.large
  static const double typeDisplayLargeFontSize = 57;

  static const FontWeight typeDisplayLargeFontWeight = FontWeight.w800;

  static const double typeDisplayLargeLineHeight = 1.1;

  // type.display.medium
  static const double typeDisplayMediumFontSize = 45;

  static const FontWeight typeDisplayMediumFontWeight = FontWeight.w800;

  static const double typeDisplayMediumLineHeight = 1.1;

  // type.display.small
  static const double typeDisplaySmallFontSize = 36;

  static const FontWeight typeDisplaySmallFontWeight = FontWeight.w700;

  static const double typeDisplaySmallLineHeight = 1.1;

  // type.headline.large
  static const double typeHeadlineLargeFontSize = 32;

  static const FontWeight typeHeadlineLargeFontWeight = FontWeight.w700;

  static const double typeHeadlineLargeLineHeight = 1.15;

  // type.headline.medium
  static const double typeHeadlineMediumFontSize = 28;

  static const FontWeight typeHeadlineMediumFontWeight = FontWeight.w700;

  static const double typeHeadlineMediumLineHeight = 1.18;

  // type.headline.small
  static const double typeHeadlineSmallFontSize = 24;

  static const FontWeight typeHeadlineSmallFontWeight = FontWeight.w700;

  static const double typeHeadlineSmallLineHeight = 1.2;

  // type.title.large
  static const double typeTitleLargeFontSize = 22;

  static const FontWeight typeTitleLargeFontWeight = FontWeight.w600;

  static const double typeTitleLargeLineHeight = 1.25;

  // type.title.subtitle
  static const double typeTitleSubtitleFontSize = 20;

  static const FontWeight typeTitleSubtitleFontWeight = FontWeight.w600;

  static const double typeTitleSubtitleLineHeight = 1.26;

  static const double typeTitleSubtitleLetterSpacing = -0.3;

  // type.title.panel-header
  static const double typeTitlePanelHeaderFontSize = 18;

  static const FontWeight typeTitlePanelHeaderFontWeight = FontWeight.w600;

  static const double typeTitlePanelHeaderLineHeight = 1.28;

  // type.title.medium
  static const double typeTitleMediumFontSize = 16;

  static const FontWeight typeTitleMediumFontWeight = FontWeight.w600;

  static const double typeTitleMediumLineHeight = 1.32;

  // type.title.row-title
  static const double typeTitleRowTitleFontSize = 15;

  static const FontWeight typeTitleRowTitleFontWeight = FontWeight.w600;

  static const double typeTitleRowTitleLineHeight = 1.3;

  // type.title.small
  static const double typeTitleSmallFontSize = 14;

  static const FontWeight typeTitleSmallFontWeight = FontWeight.w500;

  static const double typeTitleSmallLineHeight = 1.34;

  // type.body.large
  static const double typeBodyLargeFontSize = 16;

  static const FontWeight typeBodyLargeFontWeight = FontWeight.w400;

  static const double typeBodyLargeLineHeight = 1.55;

  // type.body.medium
  static const double typeBodyMediumFontSize = 14;

  static const FontWeight typeBodyMediumFontWeight = FontWeight.w400;

  static const double typeBodyMediumLineHeight = 1.45;

  // type.body.small
  static const double typeBodySmallFontSize = 12;

  static const FontWeight typeBodySmallFontWeight = FontWeight.w400;

  static const double typeBodySmallLineHeight = 1.4;

  // type.label.data
  static const double typeLabelDataFontSize = 13;

  static const FontWeight typeLabelDataFontWeight = FontWeight.w500;

  static const double typeLabelDataLineHeight = 1.3;

  // type.label.large
  static const double typeLabelLargeFontSize = 14;

  static const FontWeight typeLabelLargeFontWeight = FontWeight.w500;

  static const double typeLabelLargeLineHeight = 1.22;

  // type.label.medium
  static const double typeLabelMediumFontSize = 12;

  static const FontWeight typeLabelMediumFontWeight = FontWeight.w500;

  static const double typeLabelMediumLineHeight = 1.22;

  // type.label.small
  static const double typeLabelSmallFontSize = 11;

  static const FontWeight typeLabelSmallFontWeight = FontWeight.w500;

  static const double typeLabelSmallLineHeight = 1.22;

  // type.label.eyebrow
  static const double typeLabelEyebrowFontSize = 11;

  static const FontWeight typeLabelEyebrowFontWeight = FontWeight.w600;

  static const double typeLabelEyebrowLineHeight = 1.2;

  static const double typeLabelEyebrowLetterSpacing = 1.4;

  // type.label.chrome
  static const double typeLabelChromeFontSize = 11;

  static const FontWeight typeLabelChromeFontWeight = FontWeight.w500;

  static const double typeLabelChromeLineHeight = 1.22;
}

/// The Dark theme's semantic tokens, from `design/tokens/theme/dark.json`.
abstract final class DesignTokensDark {
  // color
  /// The app's interactive accent: filled buttons, text-button labels, selected
  /// nav, links, focus ring, progress.
  static const Color colorPrimary = DesignTokens.colorServiceSeerr;

  /// Label on a primary fill: the brand's reversed-out white.
  static const Color colorOnPrimary = DesignTokens.colorBaseWhite;

  /// Contained companion of the brand: the nav indicator, the fill a label sits
  /// on when raw indigo would miss AA.
  static const Color colorPrimaryContainer = DesignTokens.colorBrandPrimaryDark;

  /// Text on the primary container.
  static const Color colorOnPrimaryContainer =
      DesignTokens.colorBrandPrimaryLighter;

  /// Secondary indigo, one step lighter than the brand.
  static const Color colorSecondary = DesignTokens.colorBrandPrimaryLight;

  /// Label on a secondary fill.
  static const Color colorOnSecondary = DesignTokens.colorInkOnBright;

  /// Fill behind a selected segment.
  static const Color colorSecondaryContainer = colorSurfaceContainerHigh;

  /// Label on a selected segment.
  static const Color colorOnSecondaryContainer = colorOnSurfaceVariant;

  /// The success tone as a scheme role.
  static const Color colorTertiary = DesignTokens.colorStatusSuccess;

  /// Label on a success fill.
  static const Color colorOnTertiary = DesignTokens.colorInkOnBright;

  /// Filled status surface for success.
  static const Color colorTertiaryContainer =
      DesignTokens.colorStatusSuccessContainer;

  /// Text on the success container.
  static const Color colorOnTertiaryContainer = DesignTokens.colorBaseWhite;

  /// The unreachable tone as a scheme role.
  static const Color colorError = DesignTokens.colorStatusError;

  /// Label on an error fill: white measures 3.76:1 there, this ink 4.71:1.
  static const Color colorOnError = DesignTokens.colorInkOnBright;

  /// Filled status surface for error.
  static const Color colorErrorContainer =
      DesignTokens.colorStatusErrorContainer;

  /// Text on the error container.
  static const Color colorOnErrorContainer = DesignTokens.colorBaseWhite;

  /// Room Floor: the scaffold behind every screen.
  static const Color colorSurface = Color(0xFF0A0B11);

  /// Bright Label: primary text and icons on every surface and container.
  static const Color colorOnSurface = Color(0xFFF0F2F8);

  /// Sub-floor: recessed wells such as log panels and code blocks.
  static const Color colorSurfaceContainerLowest = Color(0xFF08090F);

  /// Riser: the first raised step above the floor; grouped-list backgrounds.
  static const Color colorSurfaceContainerLow = Color(0xFF11131B);

  /// Panel: cards, bottom sheets, dialogs, KPI tiles, and the navigation bar.
  static const Color colorSurfaceContainer = Color(0xFF161923);

  /// Raised Panel: secondary panels and the ground accent chips most often sit
  /// on.
  static const Color colorSurfaceContainerHigh = Color(0xFF1E2430);

  /// Instrument Face: input and chip fill, carrying on-surface-variant labels.
  static const Color colorSurfaceContainerHighest = Color(0xFF29303E);

  /// Secondary Label: metadata, chip labels, input hints, unselected nav.
  static const Color colorOnSurfaceVariant = Color(0xFFB4BCCB);

  /// Dim Label: editorial captions and tertiary metadata on surface and
  /// surface-container. Below AA on surface-container-high; use the plate dim
  /// ink on plates.
  static const Color colorDimText = Color(0xFF7C8598);

  /// Hairline: dividers, outlined buttons and cards, the rare boundary a tint
  /// cannot draw.
  static const Color colorOutline = Color(0xFF2D3748);

  /// Grouped surfaces, genre chips, KPI tile border. The same byte as outline.
  static const Color colorOutlineVariant = colorOutline;

  /// The ink every elevation level paints its shadow in.
  static const Color colorShadow = DesignTokens.colorBaseBlack;

  /// Modal barrier and hero scrims.
  static const Color colorScrim = DesignTokens.colorBaseBlack;

  /// Snackbar fill.
  static const Color colorInverseSurface = Color(0xFFF3F4F6);

  /// Snackbar text on the inverse surface.
  static const Color colorOnInverseSurface = Color(0xFF111827);

  /// The brand on an inverse surface.
  static const Color colorInversePrimary = DesignTokens.colorBrandPrimaryDark;

  // opacity
  /// Opacity of surface-container in the floating nav bar's glass fill. A tint,
  /// not a backdrop blur.
  static const double opacityGlassSurface = 0.72;

  /// Centre of the ambient accent wash behind headers and the onboarding
  /// canvas.
  static const double opacityAmbientGlow = 0.16;

  // elevation.level-1
  /// Opacity of the level-1 contact shadow.
  static const double elevationLevel1Contact = 0.28;

  /// Opacity of the level-1 ambient shadow.
  static const double elevationLevel1Ambient = 0.18;

  // elevation.level-2
  /// Opacity of the level-2 contact shadow.
  static const double elevationLevel2Contact = 0.34;

  /// Opacity of the level-2 ambient shadow.
  static const double elevationLevel2Ambient = 0.22;

  // elevation.level-3
  /// Opacity of the level-3 contact shadow.
  static const double elevationLevel3Contact = 0.4;

  /// Opacity of the level-3 ambient shadow.
  static const double elevationLevel3Ambient = 0.26;

  // elevation.glass
  /// Opacity of the glass bar's ambient shadow.
  static const double elevationGlassAmbient = 0.35;

  /// Opacity of the glass bar's 1px top highlight.
  static const double elevationGlassHighlight = 0.07;
}

/// The Light theme's semantic tokens, from `design/tokens/theme/light.json`.
abstract final class DesignTokensLight {
  // color
  /// The app's interactive accent. Indigo-600 here because primary is mostly an
  /// ink on paper: 5.71:1 on the scaffold.
  static const Color colorPrimary = DesignTokens.colorBrandPrimaryDark;

  /// Label on a primary fill: 6.29:1 on indigo-600.
  static const Color colorOnPrimary = DesignTokens.colorBaseWhite;

  /// Contained companion of the brand: the nav indicator, the fill a label sits
  /// on when raw indigo would miss AA.
  static const Color colorPrimaryContainer =
      DesignTokens.colorBrandPrimaryLighter;

  /// Text on the primary container.
  static const Color colorOnPrimaryContainer =
      DesignTokens.colorBrandPrimaryDark;

  /// Secondary indigo; the same step as primary on paper.
  static const Color colorSecondary = DesignTokens.colorBrandPrimaryDark;

  /// Label on a secondary fill.
  static const Color colorOnSecondary = DesignTokens.colorBaseWhite;

  /// Fill behind a selected segment, deliberately further from paper than the
  /// containers so the selected state reads at a glance.
  static const Color colorSecondaryContainer = Color(0xFFE2E5EE);

  /// Label on a selected segment, at full strength.
  static const Color colorOnSecondaryContainer = colorOnSurface;

  /// The success tone as a scheme role.
  static const Color colorTertiary = DesignTokens.colorStatusSuccess;

  /// Label on a success fill.
  static const Color colorOnTertiary = DesignTokens.colorInkOnBright;

  /// Filled status surface for success (green-100).
  static const Color colorTertiaryContainer = Color(0xFFDCFCE7);

  /// Text on the success container.
  static const Color colorOnTertiaryContainer =
      DesignTokens.colorStatusSuccessContainer;

  /// The unreachable tone as a scheme role.
  static const Color colorError = DesignTokens.colorStatusError;

  /// Label on an error fill: white measures 3.76:1 there, this ink 4.71:1.
  static const Color colorOnError = DesignTokens.colorInkOnBright;

  /// Filled status surface for error (red-100).
  static const Color colorErrorContainer = Color(0xFFFEE2E2);

  /// Text on the error container.
  static const Color colorOnErrorContainer =
      DesignTokens.colorStatusErrorContainer;

  /// Paper: the scaffold behind every screen.
  static const Color colorSurface = Color(0xFFF3F4F6);

  /// Ink (gray-900): primary text and icons on every surface and container.
  static const Color colorOnSurface = Color(0xFF111827);

  /// Sub-floor: recessed wells such as log panels and code blocks.
  static const Color colorSurfaceContainerLowest = DesignTokens.colorBaseWhite;

  /// Riser: grouped-list backgrounds. The same byte as surface.
  static const Color colorSurfaceContainerLow = colorSurface;

  /// Card White: cards and KPI tiles. Sheets, dialogs and the navigation bar
  /// sit on surface in this theme.
  static const Color colorSurfaceContainer = Color(0xFFFFFFFF);

  /// Cool Paper: secondary panels and the ground accent chips most often sit
  /// on.
  static const Color colorSurfaceContainerHigh = Color(0xFFF0F1F5);

  /// Warm Grey: input and chip fill, carrying on-surface-variant labels.
  static const Color colorSurfaceContainerHighest = Color(0xFFE2E4EA);

  /// Secondary Ink: metadata, chip labels, input hints, unselected nav. Clears
  /// AA on all four paper grounds (worst 5.94:1).
  static const Color colorOnSurfaceVariant = Color(0xFF4B5563);

  /// Dim Ink: editorial captions and tertiary metadata. Clears AA on all four
  /// paper grounds (worst 4.75:1).
  static const Color colorDimText = Color(0xFF5C6371);

  /// Hairline: dividers, outlined buttons and cards, the rare boundary a tint
  /// cannot draw.
  static const Color colorOutline = Color(0xFFE2E4EA);

  /// Grouped surfaces, genre chips, KPI tile border. The same byte as outline.
  static const Color colorOutlineVariant = colorOutline;

  /// The ink every elevation level paints its shadow in: ink, not black, so a
  /// shadow reads as depth rather than grime on paper.
  static const Color colorShadow = colorOnSurface;

  /// Modal barrier and hero scrims.
  static const Color colorScrim = DesignTokens.colorBaseBlack;

  /// Snackbar fill.
  static const Color colorInverseSurface = Color(0xFF0A0B11);

  /// Snackbar text on the inverse surface.
  static const Color colorOnInverseSurface = Color(0xFFF0F2F8);

  /// The brand on an inverse surface.
  static const Color colorInversePrimary = DesignTokens.colorBrandPrimaryLight;

  // opacity
  /// Opacity of surface-container in the floating nav bar's glass fill. A tint,
  /// not a backdrop blur.
  static const double opacityGlassSurface = 0.55;

  /// Centre of the ambient accent wash behind headers and the onboarding
  /// canvas.
  static const double opacityAmbientGlow = 0.1;

  // elevation.level-1
  /// Opacity of the level-1 contact shadow.
  static const double elevationLevel1Contact = 0.06;

  /// Opacity of the level-1 ambient shadow.
  static const double elevationLevel1Ambient = 0.04;

  // elevation.level-2
  /// Opacity of the level-2 contact shadow.
  static const double elevationLevel2Contact = 0.08;

  /// Opacity of the level-2 ambient shadow.
  static const double elevationLevel2Ambient = 0.05;

  // elevation.level-3
  /// Opacity of the level-3 contact shadow.
  static const double elevationLevel3Contact = 0.1;

  /// Opacity of the level-3 ambient shadow.
  static const double elevationLevel3Ambient = 0.07;

  // elevation.glass
  /// Opacity of the glass bar's ambient shadow.
  static const double elevationGlassAmbient = 0.18;

  /// Opacity of the glass bar's 1px top highlight.
  static const double elevationGlassHighlight = 0.55;
}
