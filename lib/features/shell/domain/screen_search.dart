import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

/// The focus node of the visible screen's own search field, if it has one.
///
/// `⌘F` means "search *this* screen", and only the screen knows whether it has
/// a field to search with. A registry rather than a tree walk: hunting for the
/// first `EditableText` under the content would find a rename dialog's field, a
/// YAML editor, or the filter of a collapsed section — all of them wrong, and
/// wrong in a way that only shows up in the one layout nobody tested.
final screenSearchFocusProvider = StateProvider<FocusNode?>((ref) => null);

/// Registers [focusNode] as this screen's search field while it is mounted.
///
/// Wrap the field, or place this anywhere in the screen that owns it. On
/// dispose the registration is cleared only if it is still ours: two screens
/// can overlap for a frame during a route transition, and the outgoing one must
/// not unregister the incoming one's field.
class ScreenSearchTarget extends ConsumerStatefulWidget {
  const ScreenSearchTarget({
    super.key,
    required this.focusNode,
    required this.child,
  });

  final FocusNode focusNode;
  final Widget child;

  @override
  ConsumerState<ScreenSearchTarget> createState() => _ScreenSearchTargetState();
}

class _ScreenSearchTargetState extends ConsumerState<ScreenSearchTarget> {
  @override
  void initState() {
    super.initState();
    _register(widget.focusNode);
  }

  @override
  void didUpdateWidget(ScreenSearchTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) _register(widget.focusNode);
  }

  void _register(FocusNode node) {
    // Post-frame: this runs during mount, and writing to a provider inside a
    // build phase is how you get "setState during build" a frame later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(screenSearchFocusProvider.notifier).state = node;
    });
  }

  @override
  void dispose() {
    final notifier = ref.read(screenSearchFocusProvider.notifier);
    if (notifier.state == widget.focusNode) notifier.state = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
