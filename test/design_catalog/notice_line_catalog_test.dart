@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/status_badge.dart';

import 'catalog.dart';

Widget _notice({
  required StatusTone tone,
  required String title,
  String? sentence,
  List<(String, StatusTone?)> verbs = const [],
}) => Padding(
  padding: const EdgeInsets.all(24),
  child: Builder(
    builder: (context) => NoticeLine(
      tone: tone,
      title: title,
      sentence: sentence,
      actions: [
        for (final (label, fill) in verbs)
          noticeAction(context, label, () {}, fill: fill),
      ],
    ),
  ),
);

void main() {
  final red = _notice(
    tone: StatusTone.error,
    title: "Cupola could not reach the other device",
    sentence: 'Both need to be on the same Wi-Fi.',
    verbs: const [(Lexicon.retry, null), ('Start again', null)],
  );
  final blue = _notice(
    tone: StatusTone.info,
    title: 'This code has expired',
    sentence: 'Make a new code on the other device.',
    verbs: const [('Start again', null)],
  );
  final amber = _notice(
    tone: StatusTone.warning,
    title: 'This came from a newer Cupola',
    sentence: 'Update Cupola on this device, then make a new code.',
    verbs: const [('Start again', StatusTone.warning)],
  );

  catalogCard(
    'NoticeLine',
    scenes: [
      CatalogScene(
        'NoticeLine · red: a device that did not answer, Retry and Start '
        'again, both text in ink',
        (_) => red,
        width: 390,
      ),
      CatalogScene(
        'NoticeLine · blue: a step that is the person\'s own, Start again in '
        'ink, no Retry',
        (_) => blue,
        width: 390,
      ),
      CatalogScene(
        'NoticeLine · amber: a fault, its one fill is the remedy',
        (_) => amber,
        width: 390,
      ),
      CatalogScene(
        'NoticeLine · a headline and nothing else, no verb',
        (_) =>
            _notice(tone: StatusTone.info, title: 'The Plex sign-in timed out'),
        width: 390,
      ),
      CatalogScene(
        'NoticeLine · on a desktop window: the verbs keep their 44pt floor',
        (_) => red,
        width: 480,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · the longest headline and sentence wrap; both verbs '
        'wrap onto lines of their own',
        (_) => _notice(
          tone: StatusTone.warning,
          title: "Cupola could not read what the other device sent",
          sentence: 'Make a new code on the other device.',
          verbs: const [
            (Lexicon.retry, null),
            ('Start again', StatusTone.warning),
          ],
        ),
        width: 390,
        height: 520,
        textScale: catalogTextScale,
      ),
    ],
  );
}
