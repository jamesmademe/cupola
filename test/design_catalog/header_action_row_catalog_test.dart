@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// A label painted under the 1.6× clamp, as every band label is.
Widget _clamped(Widget label) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
    child: label,
  ),
);

/// The consequence sentence, as the action band sets it under the row.
Widget _consequence(BuildContext context, String text) => Text(
  text,
  maxLines: 3,
  overflow: TextOverflow.ellipsis,
  style: Theme.of(context).textTheme.bodySmall!.copyWith(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);

ButtonStyle _discStyle(BuildContext context, ColorScheme scheme) =>
    HeaderActionRow.tonalIconButtonStyle(
      context,
      foregroundColor: scheme.onSurfaceVariant,
      backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
      borderColor: scheme.outlineVariant,
    );

Widget _disc(
  BuildContext context,
  IconData icon,
  String name, {
  bool enabled = true,
}) => SizedBox.square(
  dimension: HeaderActionRow.buttonHeight,
  child: OutlinedButton(
    onPressed: enabled ? () {} : null,
    style: _discStyle(context, Theme.of(context).colorScheme),
    child: Icon(icon, size: ActionStateGlyph.glyphSize, semanticLabel: name),
  ),
);

Widget _discs(List<Widget> discs) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (var i = 0; i < discs.length; i++) ...[
      if (i > 0) const SizedBox(width: AppSpacing.sm),
      discs[i],
    ],
  ],
);

/// A band with a promoted primary: the ink-filled expanded control (the brand book's
/// primary, the same on every service), the discs beside it, and the sentence
/// underneath.
Widget _primaryBand({
  required ServiceKey service,
  required String label,
  required IconData icon,
  required String consequence,
  bool isBusy = false,
  bool isConfirmed = false,
  bool withSecondary = true,
}) => Builder(
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.primary;
    final onFill = scheme.onPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeaderActionRow(
          expanded: FilledButton.icon(
            onPressed: isBusy ? null : () {},
            icon: ActionStateGlyph(
              icon: icon,
              label: label,
              isBusy: isBusy,
              isConfirmed: isConfirmed,
              color: onFill,
              fill: fill,
            ),
            label: _clamped(
              Text(label, maxLines: 2, textAlign: TextAlign.center),
            ),
            style: HeaderActionRow.expandedButtonStyle(
              context,
              foregroundColor: onFill,
              backgroundColor: fill,
            ),
          ),
          trailing: _discs([
            if (withSecondary)
              _disc(
                context,
                Icons.search_rounded,
                'Interactive search',
                enabled: !isBusy,
              ),
            _disc(
              context,
              Icons.more_horiz_rounded,
              'More actions',
              enabled: !isBusy,
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),
        _consequence(context, consequence),
      ],
    );
  },
);

/// A band whose primary is withheld: two labelled tonal buttons take the
/// wide slot.
Widget _tonalBand(String consequence) => Builder(
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tonal(String label) => OutlinedButton(
      onPressed: () {},
      style:
          HeaderActionRow.tonalExpandedButtonStyle(
            context,
            foregroundColor: scheme.onSurfaceVariant,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
            borderColor: scheme.outlineVariant,
          ).copyWith(
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
          ),
      child: _clamped(Text(label, maxLines: 2, textAlign: TextAlign.center)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeaderActionRow(
          expanded: Row(
            children: [
              Expanded(child: tonal('Interactive search')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: tonal('Automatic search')),
            ],
          ),
          trailing: _disc(context, Icons.more_horiz_rounded, 'More actions'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _consequence(context, consequence),
      ],
    );
  },
);

/// Nothing promoted and nothing to surface: the sentence takes the wide slot.
Widget _sentenceBand() => Builder(
  builder: (context) => HeaderActionRow(
    expanded: _consequence(
      context,
      "There's nothing to search for until it's released.",
    ),
    trailing: _disc(context, Icons.more_horiz_rounded, 'More actions'),
  ),
);

/// The captioned button's own states, side by side.
Widget _buttonStates() => const Wrap(
  spacing: AppSpacing.sm,
  runSpacing: AppSpacing.md,
  children: [
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
      onPressed: _noop,
    ),
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
      onPressed: _noop,
      isBusy: true,
    ),
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
      onPressed: _noop,
      isConfirmed: true,
    ),
    HeaderActionButton(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      semanticLabel: 'Automatic search',
    ),
    HeaderActionButton(
      icon: Icons.manage_search_rounded,
      label: 'Interactive search',
      onPressed: _noop,
    ),
  ],
);

void _noop() {}

List<CatalogScene> _bands(CatalogPlatform platform, double width) => [
  CatalogScene(
    'Primary + two discs · Radarr, Automatic search · the ink fill with the '
    'on-ink label, 52pt tall (button-l), radius.button: never the service\'s colour',
    (_) => _primaryBand(
      service: ServiceKey.radarr,
      label: 'Automatic search',
      icon: Icons.saved_search_rounded,
      consequence: 'Radarr is hunting a release for this title.',
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Primary busy · Sonarr · a 16pt spinner for this control only; the discs '
    'stay in place, disabled',
    (_) => _primaryBand(
      service: ServiceKey.sonarr,
      label: 'Automatic search',
      icon: Icons.saved_search_rounded,
      consequence: 'Sonarr is hunting a release for this title.',
      isBusy: true,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Primary confirmed · Lidarr · the success check walked against the '
    'ink fill',
    (_) => _primaryBand(
      service: ServiceKey.lidarr,
      label: 'Automatic search',
      icon: Icons.saved_search_rounded,
      consequence: 'Lidarr is hunting a release for this title.',
      isConfirmed: true,
      withSecondary: false,
    ),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Primary withheld · two tonal buttons take the wide slot, no glyph',
    (_) =>
        _tonalBand("Radarr has everything it expects, so it isn't searching."),
    width: width,
    platform: platform,
  ),
  CatalogScene(
    'Nothing to promote · the sentence takes the expanded slot',
    (_) => _sentenceBand(),
    width: width,
    platform: platform,
  ),
];

void main() {
  catalogCard(
    'HeaderActionRow',
    width: 720,
    scenes: [
      ..._bands(CatalogPlatform.phone, 390),
      CatalogScene(
        'HeaderActionButton · idle, busy, confirmed, onPressed: null, long '
        'caption · a 52pt square in a 72pt measure, caption wraps to two lines',
        (_) => _buttonStates(),
      ),
      CatalogScene(
        'At 2× reading size · the library band: the primary label and the '
        'consequence sentence take the lines they need, the discs keep 52pt',
        (_) => _primaryBand(
          service: ServiceKey.radarr,
          label: 'Automatic search',
          icon: Icons.saved_search_rounded,
          consequence: 'Radarr is hunting a release for this title.',
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      ..._bands(CatalogPlatform.desktop, 560),
    ],
  );
}
