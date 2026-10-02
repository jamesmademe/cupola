import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/focus_ring.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';

/// The keyboard's place is a ring (brand book, *Lines and fills*: the focus
/// ring and a focused field are `line.focus`). A focused filled button used
/// to change only its shade, and the search field showed nothing but a caret.
void main() {
  for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
    final room = CupolaRoom.forBrightness(theme.brightness);
    final name = theme.brightness.name;

    final styles = <String, ButtonStyle?>{
      'filled': theme.filledButtonTheme.style,
      'outlined': theme.outlinedButtonTheme.style,
      'text': theme.textButtonTheme.style,
      'icon': theme.iconButtonTheme.style,
    };

    styles.forEach((button, style) {
      test('$name: a focused $button button is ringed in line.focus', () {
        final focused = style!.shape!.resolve({WidgetState.focused});
        expect(focused, isA<FocusRingBorder>());
        expect((focused! as FocusRingBorder).color, room.focus);
        // Outside the shape and apart from it.
        expect((focused as FocusRingBorder).gap, greaterThan(0));
        expect(style.shape!.resolve({}), isNot(isA<FocusRingBorder>()));
      });
    });

    testWidgets('$name: a focused search field is edged in line.focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SearchBarHeader(
                hintText: 'Search movies',
                autofocus: true,
                onQueryChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final shape = tester.widget<SearchBar>(find.byType(SearchBar)).shape!;
      final focused = shape.resolve({WidgetState.focused})!;
      expect(focused.side.color, room.focus);
      expect(shape.resolve({})!.side.color, isNot(room.focus));
    });
  }

  testWidgets('a button the keyboard focuses wears the ring', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Grab'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Material),
      ),
    );
    expect(material.shape, isA<FocusRingBorder>());
  });

  testWidgets('the detail band rings its own shapes', (tester) async {
    late List<ButtonStyle> styles;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) {
            styles = [
              HeaderActionRow.expandedButtonStyle(context),
              HeaderActionRow.iconOnlyButtonStyle(context),
              HeaderActionRow.tonalIconButtonStyle(
                context,
                foregroundColor: Colors.white,
                backgroundColor: Colors.black,
                borderColor: Colors.grey,
              ),
              HeaderActionRow.tonalExpandedButtonStyle(
                context,
                foregroundColor: Colors.white,
                backgroundColor: Colors.black,
                borderColor: Colors.grey,
              ),
            ];
            return const SizedBox();
          },
        ),
      ),
    );
    for (final style in styles) {
      final focused = style.shape!.resolve({WidgetState.focused});
      expect(focused, isA<FocusRingBorder>());
      expect((focused! as FocusRingBorder).color, CupolaRoom.dark.focus);
    }
  });
}
