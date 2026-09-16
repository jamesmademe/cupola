import 'dart:async';

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
  /// The registry itself, held rather than re-read on the way out.
  ///
  /// `ref` is a `BuildContext` in disguise, and Riverpod throws outright the
  /// moment it is touched after the element leaves the tree — which is exactly
  /// where deregistration has to happen. Its own error text prescribes this:
  /// keep the provider's state in a field of the State. Safe to hold because
  /// `screenSearchFocusProvider` is a root, non-autoDispose provider, so the
  /// controller lives as long as the container above us.
  StateController<FocusNode?>? _registry;

  /// Which registration is the current one, app-wide, and which one was ours.
  ///
  /// Because deregistration is deferred (see [dispose]), "is the registry still
  /// ours?" can no longer be answered by the node alone. A screen whose element
  /// is rebuilt into a new position re-registers *the same node* from a new
  /// State before the old State's deferred clear runs, and a clear keyed on the
  /// node would then quietly kill a live field — ⌘F dead with nothing on screen
  /// to say so. The serial asks the question that actually matters: has anyone
  /// registered since we did.
  static int _registrationSerial = 0;
  int? _ourRegistration;

  @override
  void initState() {
    super.initState();
    _register(widget.focusNode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: the enclosing ProviderScope is an inherited widget, and
    // this is the first point the framework guarantees it is resolvable.
    _registry = ref.read(screenSearchFocusProvider.notifier);
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
      // The held registry rather than `ref`, for the same reason dispose uses
      // it: a screen mounted and popped inside one frame is deactivated but
      // still `mounted`, and `ref` throws in that window.
      final registry = _registry;
      if (registry == null || !registry.mounted) return;
      _ourRegistration = ++_registrationSerial;
      registry.state = node;
    });
  }

  @override
  void dispose() {
    final registry = _registry;
    final ours = widget.focusNode;
    final registration = _ourRegistration;
    // Deferred, and not merely moved off `ref`: dispose runs inside the build
    // owner's state lock, and Riverpod refuses a provider write there outright —
    // the same refusal that covers build, initState and didChangeDependencies.
    // Reading the notifier here throws for a second reason on top of that: `ref`
    // is a BuildContext, and by dispose it has been deactivated. This branch ran
    // on every teardown of a ⌘F-capable screen, so both were one pop away.
    scheduleMicrotask(() {
      // `mounted` covers the one ordering this cannot control: a container torn
      // down above us. Writing to a disposed controller throws, and a crash on
      // the way out of the app would be this bug again, somewhere harder to see.
      if (registration == null || registry == null || !registry.mounted) return;
      if (registration != _registrationSerial) return;
      if (registry.state == ours) registry.state = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
