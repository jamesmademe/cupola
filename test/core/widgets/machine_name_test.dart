import 'package:flutter/semantics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/machine_name.dart';

const _file = 'Avengers.Endgame.2019.2160p.UHD.BluRay.x265-GROUP.mkv';
const _release = 'Severance.S02E05.1080p.WEB-DL.DDP5.1-GROUP';

/// Ten units a character: the arithmetic of a mono face, without the face.
double _tenEach(String value) => value.characters.length * 10.0;

/// What the clipboard last received, through the platform channel.
String? _clipboard;

void _mockClipboard(WidgetTester tester) {
  _clipboard = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          _clipboard = (call.arguments as Map)['text'] as String?;
        case 'Clipboard.getData':
          return {'text': _clipboard};
        case 'Clipboard.hasStrings':
          return {'value': _clipboard != null};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// The text a row variant draws.
String _drawn(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(of: find.byType(MachineName), matching: find.byType(Text)),
  );
  return text.data!;
}

void main() {
  group('elideMachineName', () {
    test('a name that fits is drawn whole', () {
      expect(elideMachineName(_file, maxWidth: 1000, widthOf: _tenEach), _file);
      expect(
        elideMachineName(_file, maxWidth: double.infinity, widthOf: _tenEach),
        _file,
      );
    });

    test('keeps both ends and the extension whole, the ellipsis in the '
        'middle', () {
      final shown = elideMachineName(_file, maxWidth: 360, widthOf: _tenEach);
      expect(shown, 'Avengers.Endgame.2…ay.x265-GROUP.mkv');
      expect(_tenEach(shown), lessThanOrEqualTo(360));
      expect('…'.allMatches(shown), hasLength(1));
    });

    test('takes the longest form that fits', () {
      for (final width in [120.0, 200.0, 290.0, 400.0, 520.0]) {
        final shown = elideMachineName(
          _file,
          maxWidth: width,
          widthOf: _tenEach,
        );
        expect(_tenEach(shown), lessThanOrEqualTo(width), reason: '$width');
        // One more character on either side would not have fitted.
        expect(_tenEach(shown) + 10, greaterThan(width - 20), reason: shown);
        expect(shown, endsWith('.mkv'), reason: shown);
      }
    });

    test('never lets a separator touch the ellipsis', () {
      for (var width = 60.0; width < 530; width += 10) {
        final shown = elideMachineName(
          _file,
          maxWidth: width,
          widthOf: _tenEach,
        );
        final at = shown.indexOf('…');
        if (at > 0) {
          expect(shown[at - 1], isNot(anyOf('.', '-', '_')), reason: shown);
        }
        final after = shown.substring(at + 1);
        // The extension's own dot may follow when nothing else is left.
        if (after != '.mkv') {
          expect(after[0], isNot(anyOf('.', '-', '_')), reason: shown);
        }
      }
    });

    test('keeps the extension when nothing else fits', () {
      expect(elideMachineName(_file, maxWidth: 50, widthOf: _tenEach), '….mkv');
      // Narrower still: the extension, clipped by the line, never cut.
      expect(elideMachineName(_file, maxWidth: 20, widthOf: _tenEach), '….mkv');
    });

    test('a release name has no extension to protect, so both halves share '
        'the room', () {
      final shown = elideMachineName(
        _release,
        maxWidth: 300,
        widthOf: _tenEach,
      );
      expect(shown, 'Severance.S02E0…L.DDP5.1-GROUP');
    });
  });

  group('machineNameWithBreaks', () {
    test(
      'offers a break after every dot and underscore, none at the end or before the extension',
      () {
        expect(
          machineNameWithBreaks('Coffee.Run_2020.mkv'),
          'Coffee.\u200BRun_\u200B2020.mkv',
        );
        expect(machineNameWithBreaks('ends.'), 'ends.');
      },
    );

    testWidgets('a wrapped name breaks after a separator, never inside a '
        'segment', (tester) async {
      final painter = TextPainter(
        text: TextSpan(text: machineNameWithBreaks(_file), style: AppType.mono),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 220);
      addTearDown(painter.dispose);
      final text = painter.plainText;
      final lines = painter.computeLineMetrics();
      expect(lines.length, greaterThan(1));
      for (final line in lines.skip(1)) {
        final start = painter
            .getPositionForOffset(Offset(1, line.baseline - line.ascent + 1))
            .offset;
        expect(text[start - 1], anyOf('\u200B', '-'), reason: text);
      }
    });

    test('draws a name that already carries a zero-width space as it came', () {
      const odd = 'a\u200Bb.c';
      expect(machineNameWithBreaks(odd), odd);
    });
  });

  group('MachineName in a row', () {
    testWidgets('draws one mono line in the tertiary ink, the ellipsis in the '
        'middle when it does not fit', (tester) async {
      await _pump(tester, const MachineName.file(_file), width: 200);

      final shown = _drawn(tester);
      expect(shown, contains('…'));
      expect(shown, startsWith('Aven'));
      expect(shown, endsWith('.mkv'));

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(MachineName),
          matching: find.byType(Text),
        ),
      );
      expect(text.maxLines, 1);
      expect(text.style!.fontFamily, AppTheme.monoFontFamily);
      final context = tester.element(find.byType(MachineName));
      expect(text.style!.color, CupolaThemeColors.of(context).dimText);
      // One line, in the box it was given.
      expect(
        tester.getSize(find.byType(MachineName)).height,
        lessThan(2 * text.style!.fontSize! * text.style!.height!),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a name that fits whole, with no tooltip', (
      tester,
    ) async {
      await _pump(tester, const MachineName.file('Spring.mkv'), width: 360);
      expect(_drawn(tester), 'Spring.mkv');
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('an elided name carries the whole one as a hover tooltip, '
        'silent to a screen reader', (tester) async {
      await _pump(tester, const MachineName.file(_file), width: 200);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.richMessage!.toPlainText(), _file);
      expect(tooltip.triggerMode, TooltipTriggerMode.manual);
      expect(tooltip.excludeFromSemantics, isTrue);
    });

    testWidgets('re-elides when the width changes', (tester) async {
      await _pump(tester, const MachineName.file(_file), width: 200);
      final narrow = _drawn(tester);
      await _pump(tester, const MachineName.file(_file), width: 320);
      final wider = _drawn(tester);
      expect(wider.length, greaterThan(narrow.length));
      await _pump(tester, const MachineName.file(_file), width: 900);
      expect(_drawn(tester), _file);
    });

    testWidgets('stays out of the row sentence and gives the row the copy '
        'action', (tester) async {
      const host = ValueKey('row');
      await _pump(
        tester,
        Semantics(
          key: host,
          container: true,
          label: 'Severance, downloading',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Text('Severance')),
              MachineName.release(_release),
            ],
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byKey(host)),
        containsSemantics(
          label: 'Severance, downloading',
          customActions: const [
            CustomSemanticsAction(label: 'Copy release name'),
          ],
        ),
      );
      expect(find.bySemanticsLabel(RegExp('GROUP')), findsNothing);
    });

    testWidgets('a long press copies the name exactly and says so', (
      tester,
    ) async {
      _mockClipboard(tester);
      await _pump(tester, const MachineName.file(_file), width: 200);

      await tester.longPress(find.byType(MachineName));
      await tester.pump();

      expect(_clipboard, _file);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('the screen-reader action copies the name', (tester) async {
      _mockClipboard(tester);
      await _pump(tester, const MachineName.release(_release));

      final node = tester.getSemantics(find.byType(MachineName));
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Copy release name'),
        ),
      );
      await tester.pump();

      expect(_clipboard, _release);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('a secondary click opens a menu whose one item copies', (
      tester,
    ) async {
      _mockClipboard(tester);
      await _pump(tester, const MachineName.file(_file), width: 200);

      await tester.tap(find.byType(MachineName), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Copy file name'), findsOneWidget);

      await tester.tap(find.text('Copy file name'));
      await tester.pumpAndSettle();

      expect(_clipboard, _file);
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('MachineName in full', () {
    String drawnInFull(WidgetTester tester) => tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .toPlainText();

    testWidgets('draws the whole name, wrapping after its dots', (
      tester,
    ) async {
      await _pump(tester, const MachineName.fileInFull(_file), width: 220);

      expect(drawnInFull(tester).replaceAll('\u200B', ''), _file);
      final line = AppType.mono.fontSize! * AppType.mono.height!;
      expect(
        tester.getSize(find.byType(SelectableText)).height,
        greaterThan(line * 1.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a caption is drawn ahead of the name and read with it', (
      tester,
    ) async {
      await _pump(
        tester,
        const MachineName.releaseInFull(_release, caption: 'Released as'),
      );

      expect(
        drawnInFull(tester).replaceAll('\u200B', ''),
        'Released as $_release',
      );
      expect(find.semantics.byLabel('Released as'), findsOne);
      expect(
        tester.getSemantics(
          find
              .ancestor(
                of: find.byType(SelectableText),
                matching: find.byType(Semantics),
              )
              .first,
        ),
        containsSemantics(
          label: 'Released as',
          value: _release,
          customActions: const [
            CustomSemanticsAction(label: 'Copy release name'),
          ],
        ),
      );
    });

    testWidgets('is read whole after its label, beside a copy button', (
      tester,
    ) async {
      await _pump(tester, const MachineName.fileInFull(_file));

      expect(find.semantics.byLabel('File name'), findsOne);
      final node = tester.getSemantics(
        find
            .ancestor(
              of: find.byType(SelectableText),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.label, 'File name');
      expect(node.value, _file);
      expect(
        tester.getSemantics(find.byType(IconButton)),
        containsSemantics(
          tooltip: 'Copy file name',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('the copy button copies the name exactly and says so', (
      tester,
    ) async {
      _mockClipboard(tester);
      await _pump(tester, const MachineName.fileInFull(_file));

      await tester.tap(find.byTooltip('Copy file name'));
      await tester.pump();

      expect(_clipboard, _file);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('a selection copied from the keyboard carries none of the '
        'break opportunities', (tester) async {
      _mockClipboard(tester);
      await _pump(tester, const MachineName.fileInFull(_file), width: 220);

      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(_clipboard, _file);
    });

    testWidgets('the selection toolbar copies exactly and offers nothing that '
        'would hand the drawn text on', (tester) async {
      _mockClipboard(tester);
      await _pump(tester, const MachineName.fileInFull(_file), width: 220);

      await tester.longPress(find.byType(SelectableText));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsNothing);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(_clipboard, _file);
    });

    for (final (platform, floor) in [
      (TargetPlatform.iOS, 44.0),
      (TargetPlatform.android, 44.0),
      (TargetPlatform.macOS, 38.0),
      (TargetPlatform.windows, 38.0),
    ]) {
      testWidgets('${platform.name}: the copy button keeps its $floor target', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        final theme = AppTheme.darkTheme();
        debugDefaultTargetPlatformOverride = null;
        await _pump(
          tester,
          const MachineName.fileInFull(_file),
          theme: theme.copyWith(platform: platform),
        );
        final size = tester.getSize(find.byType(IconButton));
        expect(size.width, greaterThanOrEqualTo(floor));
        expect(size.height, greaterThanOrEqualTo(floor));
      });
    }
  });
}
