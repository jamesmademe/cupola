import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

/// Where the inspector is, and how wide.
@immutable
class InspectorState {
  const InspectorState({required this.open, required this.width});

  /// Whether the pane is showing.
  final bool open;

  /// Its width in logical pixels, already clamped to [minWidth]..[maxWidth].
  final double width;

  /// The design width, and what a double-click on the handle restores.
  static const double defaultWidth = 360;

  /// Narrower than this and the queue rows lose their figures; wider and the
  /// content well starts giving up its second column. Both are the pane's own
  /// content talking, which is why they live with the state and not in a layout.
  static const double minWidth = 300;
  static const double maxWidth = 520;

  InspectorState copyWith({bool? open, double? width}) => InspectorState(
    open: open ?? this.open,
    width: (width ?? this.width).clamp(minWidth, maxWidth),
  );
}

/// The inspector's position, remembered across launches.
///
/// Persisted rather than session-only because the pane is a *workspace*
/// decision, not a navigation one: somebody who drags it to 480 and closes the
/// app has told us where they want it. Keyed plainly rather than per-window:
/// the app is single-window today, and a key that pretended otherwise would be
/// a migration waiting to happen.
final inspectorStateProvider =
    NotifierProvider<InspectorStateNotifier, InspectorState>(
      InspectorStateNotifier.new,
    );

class InspectorStateNotifier extends Notifier<InspectorState> {
  static const _openKey = 'inspector_open';
  static const _widthKey = 'inspector_width';

  @override
  InspectorState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return InspectorState(
      // Closed by default. The inspector is an accelerator, and a first-run
      // window that opens with two thirds of its width spoken for teaches the
      // wrong thing about where the app's content lives.
      open: prefs.getBool(_openKey) ?? false,
      width: (prefs.getDouble(_widthKey) ?? InspectorState.defaultWidth).clamp(
        InspectorState.minWidth,
        InspectorState.maxWidth,
      ),
    );
  }

  void toggle() => _write(state.copyWith(open: !state.open));

  void setOpen(bool open) {
    if (state.open == open) return;
    _write(state.copyWith(open: open));
  }

  /// Applies a drag delta. The clamp lives in [InspectorState.copyWith], so a
  /// drag that runs past either end simply stops instead of inverting the pane.
  void resizeBy(double delta) =>
      _write(state.copyWith(width: state.width - delta));

  /// Double-click on the handle: back to the drawn width.
  void resetWidth() =>
      _write(state.copyWith(width: InspectorState.defaultWidth));

  void _write(InspectorState next) {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setBool(_openKey, next.open);
    prefs.setDouble(_widthKey, next.width);
  }
}
