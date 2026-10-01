import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Bazarr-specific detail sections. Feature-local on purpose: no other
/// service has a subtitle-language axis, so these do not belong in
/// `core/widgets`.

/// A wrap of subtitle-language cards (code, full name, forced/HI) — the missing
/// languages or the ones on disk; the slot label around it says which.
class BazarrSubtitleLanguageWrap extends StatelessWidget {
  final List<BazarrSubtitleLanguage> languages;

  const BazarrSubtitleLanguageWrap({super.key, required this.languages});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The accent is not a legible label colour over its own tint in light
    // theme (Luminance Rule); onTint walks its lightness until it clears AA.
    final accentText = ServiceTheme.onTint(
      ServiceKey.bazarr.accent,
      surface: colorScheme.surface,
      tintAlpha: 0.12,
    );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final lang in languages)
          Semantics(
            container: true,
            excludeSemantics: true,
            // Uppercase belongs in the eye, not in the ear — speak the full
            // name, and spell the flags out as words.
            label: [
              lang.name ?? lang.code2 ?? 'Unknown language',
              if (lang.forced) 'forced',
              if (lang.hi) 'hearing impaired',
            ].join(', '),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: ServiceKey.bazarr.accent.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusSm,
                border: Border.all(
                  color: ServiceKey.bazarr.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (lang.code2 ?? lang.name ?? '?').toUpperCase(),
                    style: Theme.of(context).textTheme.titleSmall!
                        .weight(FontWeight.w600)
                        .copyWith(color: accentText),
                  ),
                  if (lang.name != null && lang.code2 != null)
                    Text(
                      lang.name!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (lang.forced || lang.hi)
                    Text(
                      [
                        if (lang.forced) 'forced',
                        if (lang.hi) 'hi',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One wanted episode row, on the shared dense-row primitive.
///
/// Was the fourth hand-rolled dense row in the app — its own `Container` shell
/// instead of [AppCard], a fixed 36x36 leading box, a magic `vertical: 3`
/// padding, `maxLines: 1` on a service-supplied title, and no press feedback at
/// all. [MediaChildTile.numbered] is the same shape the Sonarr, Seerr and Lidarr
/// child regions already speak, so a wanted episode here now looks and sounds
/// like an episode everywhere else.
class BazarrWantedEpisodeTile extends StatelessWidget {
  final BazarrWantedItem item;

  const BazarrWantedEpisodeTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final langNames = item.missingLanguages
        .map((l) => l.name ?? l.code2)
        .whereType<String>()
        .join(', ');
    // The whole code, not the episode alone: the list is one series' wanted
    // episodes across all its seasons, under no season heading.
    final ordinal = item.episodeCode;

    return MediaChildTile.numbered(
      ordinal: ordinal,
      // `S2 E4` reads as letters and digits without this.
      ordinalLabel: item.spokenEpisode ?? '',
      title: item.episodeTitle ?? item.spokenEpisode ?? 'Episode ?',
      // The languages in words, not a colour-only badge: this row's whole
      // subject is which subtitles are absent, so it has to say so.
      facts: [if (langNames.isNotEmpty) 'Missing $langNames' else 'Wanted'],
    );
  }
}

/// What a section draws in place of its own failure while the page's line
/// already says Bazarr did not answer: the gap, named once, without the alarm
/// a second time.
///
/// A second failure state for the same silence used to sit under the first,
/// with its own headline and its own Retry. The page's line is the one place
/// that says it; this only says why the section is empty.
class BazarrAwaitingNote extends StatelessWidget {
  const BazarrAwaitingNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: CupolaThemeColors.of(context).dimText,
        ),
      ),
    );
  }
}
