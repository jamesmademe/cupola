@Tags(['catalog'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/reel_command_button.dart';

import 'catalog.dart';

const _slot = ['Test connection', 'Test again', 'Next service'];

Future<void> _forever() => Completer<void>().future;

/// Presses the button inside it once, after the first frame, with a future
/// that never resolves — so the scene is drawn mid-wait.
class _Pressed extends StatefulWidget {
  const _Pressed({required this.child});

  final Widget child;

  @override
  State<_Pressed> createState() => _PressedState();
}

class _PressedState extends State<_Pressed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void press(Element element) {
        final widget = element.widget;
        if (widget is FilledButton) {
          widget.onPressed?.call();
          return;
        }
        element.visitChildren(press);
      }

      context.visitChildElements(press);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget _test({String label = 'Test connection', bool enabled = true}) =>
    ReelCommandButton(
      label: label,
      busyLabel: 'Testing',
      failureLabel: 'Test again',
      slotLabels: _slot,
      onPressed: enabled ? _forever : null,
    );

Widget _reduced(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

List<CatalogScene> _scenes(CatalogPlatform platform) => [
  CatalogScene(
    'Rest · Test connection · the slot is already as wide as the widest '
    'label it will hold, so the text sits centred in spare room',
    (_) => _test(),
    platform: platform,
  ),
  CatalogScene(
    'Waiting · pressed, future in flight · disabled, the label keeps its '
    'word and the dots roll in on a loop; spoken "Testing"',
    (_) => _Pressed(child: _test()),
    platform: platform,
  ),
  CatalogScene(
    'Answered · rolled to Next service, same button, same width',
    (_) => _test(label: 'Next service'),
    platform: platform,
  ),
  CatalogScene(
    'Failed, settled · Test again · what pressing it again will do, not '
    '"Failed"',
    (_) => _test(label: 'Test again'),
    platform: platform,
  ),
  CatalogScene(
    'onPressed: null · Material disabled, the reservation kept',
    (_) => _test(enabled: false),
    platform: platform,
  ),
];

void main() {
  catalogCard(
    'ReelCommandButton',
    width: 560,
    scenes: [
      ..._scenes(CatalogPlatform.phone),
      CatalogScene(
        'Reduce Motion, waiting · one settled "Testing", no dots and no timer',
        (_) => _reduced(_Pressed(child: _test())),
      ),
      CatalogScene(
        'busyLabel: null · Continue with 4, slot reserved for Continue with '
        '17 · a tap runs the action and the label rolls when the parent '
        'changes it',
        (_) => ReelCommandButton(
          label: 'Continue with 4',
          slotLabels: const ['Continue with 17'],
          onPressed: () async {},
        ),
      ),
      CatalogScene(
        'Enter Cupola · busyLabel Opening, the finish step\'s button',
        (_) => ReelCommandButton(
          label: 'Enter Cupola',
          busyLabel: 'Opening',
          onPressed: () async {},
        ),
      ),
      CatalogScene(
        'A long label · on a 280pt measure the slot holds the widest label it '
        'will roll to (Continue to the next service), and the resting one '
        'sits centred in it',
        (_) => ReelCommandButton(
          label: 'Test every connection',
          busyLabel: 'Testing every connection',
          failureLabel: 'Test every connection again',
          slotLabels: const ['Continue to the next service'],
          onPressed: _forever,
        ),
        width: 280,
      ),
      CatalogScene(
        'Text at 200% · rest, waiting and disabled: the slot measures the '
        'widest label at the reading size',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _test(),
            const SizedBox(height: 12),
            _Pressed(child: _test()),
            const SizedBox(height: 12),
            _test(enabled: false),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      ..._scenes(CatalogPlatform.desktop),
    ],
  );
}
