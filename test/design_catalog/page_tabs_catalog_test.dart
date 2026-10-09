@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/page_tabs.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';

import 'catalog.dart';

/// The four views of Activity at the head of the page, on the page's gutter.
Widget _tabs(ActivityTab selected) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: PageTabs<ActivityTab>(
    values: ActivityTab.values,
    selected: selected,
    labelBuilder: (tab) => tab.label,
    onSelected: (_) {},
    semanticLabel: 'Activity views',
  ),
);

void main() {
  catalogCard(
    'PageTabs',
    scenes: [
      CatalogScene(
        'PageTabs<ActivityTab>() · All is the page: the four views share '
        'one track, the selected one on the primary ink fill',
        (_) => _tabs(ActivityTab.all),
        width: 390,
      ),
      CatalogScene(
        'PageTabs<ActivityTab>() · Downloads selected: the thumb is the '
        'page\'s, never a service\'s colour',
        (_) => _tabs(ActivityTab.downloads),
        width: 390,
      ),
      CatalogScene(
        'PageTabs<ActivityTab>() · Requests and History selected, on the '
        'widest phone',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tabs(ActivityTab.requests),
            const SizedBox(height: 12),
            _tabs(ActivityTab.history),
          ],
        ),
        width: 430,
      ),
      CatalogScene(
        'PageTabs<String>() · a long label no longer fits its share, so the '
        'track lays the four two by two at the default reading size',
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PageTabs<String>(
            values: const ['All', 'Downloads', 'Needs approval', 'History'],
            selected: 'Needs approval',
            labelBuilder: (label) => label,
            onSelected: (_) {},
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · the four views two by two, none cut and every '
        'segment 44 tall at least',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tabs(ActivityTab.all),
            const SizedBox(height: 12),
            _tabs(ActivityTab.history),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · on a 430pt phone, Downloads selected',
        (_) => _tabs(ActivityTab.downloads),
        width: 430,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'PageTabs<ActivityTab>() · on the desktop, in the page well: the '
        'same track, the same target',
        (_) => _tabs(ActivityTab.requests),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · on the desktop, in the page well',
        (_) => _tabs(ActivityTab.all),
        width: 560,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}
