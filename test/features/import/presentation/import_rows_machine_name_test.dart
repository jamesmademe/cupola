import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/machine_name.dart';
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/blocked_import_parts.dart';
import 'package:cupola/features/import/presentation/manual_import_review_rows.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/blocked_import_world.dart';

const _copyFile = 'Copy file name';

ManualImportItem _clear() => ManualImportItem.fromJson(cosmosClearFile(1, 1));
ManualImportItem _tape() => ManualImportItem.fromJson(cosmosTapeFile(1));

Future<void> _pump(WidgetTester tester, Widget row, {double width = 390}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: row),
          ),
        ),
      ),
    ),
  );
}

SemanticsOwner _owner(WidgetTester tester) =>
    tester.renderObject(find.byType(Scaffold)).owner!.semanticsOwner!;

int _copyId() => CustomSemanticsAction.getIdentifier(
  const CustomSemanticsAction(label: _copyFile),
);

/// How many nodes of the tree offer the copy action: the row's own, and only
/// that one.
int _nodesWithCopy(WidgetTester tester) {
  var count = 0;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().customSemanticsActionIds?.contains(_copyId()) ??
        false) {
      count++;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(_owner(tester).rootSemanticsNode!);
  return count;
}

bool _offersCopy(SemanticsNode node) =>
    node.getSemanticsData().customSemanticsActionIds?.contains(_copyId()) ??
    false;

void main() {
  final clear = _clear();
  final tape = _tape();

  testWidgets('a matched row draws its file as a MachineName and offers copy '
      'on the node it speaks from', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      MatchedFileRow.ready(
        service: ServiceKey.sonarr,
        item: clear,
        groupTitle: 'Kosmische Wasserette',
        underGroupHeader: false,
        selected: false,
        onSelectedChanged: (_) {},
        onOpenOptions: () {},
      ),
    );

    expect(find.byType(MachineName), findsOneWidget);
    final row = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^Kosmische Wasserette')).first,
    );
    expect(_offersCopy(row), isTrue);
    expect(row.value, contains(clear.fileName));
    expect(_nodesWithCopy(tester), 1);
    handle.dispose();
  });

  testWidgets(
    'copying from the row puts the exact file name on the clipboard',
    (tester) async {
      final handle = tester.ensureSemantics();
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
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
      await _pump(
        tester,
        OtherFileRow(service: ServiceKey.sonarr, item: clear),
      );

      final row = tester.getSemantics(
        find.bySemanticsLabel(RegExp(RegExp.escape(clear.fileName))).first,
      );
      _owner(
        tester,
      ).performAction(row.id, SemanticsAction.customAction, _copyId());
      await tester.pump();
      expect(clipboard, clear.fileName);
      await tester.pump(const Duration(seconds: 5));
      handle.dispose();
    },
  );

  testWidgets('an unmatched row, a silenced row and an in-flight row keep '
      'their sentence and gain the copy action', (tester) async {
    final handle = tester.ensureSemantics();

    await _pump(
      tester,
      AttentionFileRow(
        service: ServiceKey.sonarr,
        item: tape,
        picked: false,
        onPickedChanged: (_) {},
        onFix: () {},
      ),
    );
    var row = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^${RegExp.escape(tape.fileName)}')).first,
    );
    expect(_offersCopy(row), isTrue);
    expect(row.hint, 'opens match assignment');
    expect(_nodesWithCopy(tester), 1);

    await _pump(tester, OtherFileRow(service: ServiceKey.sonarr, item: clear));
    row = tester.getSemantics(
      find.bySemanticsLabel(RegExp(RegExp.escape(clear.fileName))).first,
    );
    expect(_offersCopy(row), isTrue);
    expect(row.label, clear.fileName);
    expect(_nodesWithCopy(tester), 1);

    await _pump(
      tester,
      InFlightFileRow(
        service: ServiceKey.sonarr,
        item: clear,
        command: ManualImportCommandStatus.fromJson(const {
          'id': 1,
          'status': 'started',
        }),
      ),
    );
    row = tester.getSemantics(find.byType(AppCard));
    expect(_offersCopy(row), isTrue);
    expect(row.value, startsWith(clear.fileName));
    expect(_nodesWithCopy(tester), 1);
    handle.dispose();
  });

  testWidgets('the blocked-import rows offer it on the node they speak from', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      BlockedImportClearGroup(
        service: ServiceKey.sonarr,
        title: 'Kosmische Wasserette',
        files: [clear],
        selected: const {},
        onToggle: (_, _) {},
        onAll: (_, _) {},
      ),
    );
    var row = tester.getSemantics(
      find.bySemanticsLabel(RegExp(RegExp.escape(clear.fileName))).first,
    );
    expect(_offersCopy(row), isTrue);
    expect(_nodesWithCopy(tester), 1);

    await _pump(
      tester,
      BlockedImportNeedYouRow(
        service: ServiceKey.sonarr,
        item: tape,
        kind: NeedYouKind.episode,
        selected: false,
        open: false,
        onOpen: () {},
        onPlaced: () {},
      ),
    );
    row = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^${RegExp.escape(tape.fileName)}')).first,
    );
    expect(_offersCopy(row), isTrue);
    expect(_nodesWithCopy(tester), 1);
    handle.dispose();
  });

  testWidgets('at a narrow width the name keeps its extension', (tester) async {
    await _pump(
      tester,
      OtherFileRow(
        service: ServiceKey.sonarr,
        item: ManualImportItem.fromJson({
          'path': '/downloads/$_long',
          'name': _long.replaceFirst('.mkv', ''),
          'size': 1,
        }),
      ),
      width: 200,
    );
    final drawn = tester.widget<Text>(
      find.descendant(
        of: find.byType(MachineName),
        matching: find.byType(Text),
      ),
    );
    expect(drawn.data, contains('…'));
    expect(drawn.data, endsWith('.mkv'));
  });
}

const _long = 'Kosmische.Wasserette.S01E01.2160p.UHD.BluRay.x265-GROUP.mkv';
