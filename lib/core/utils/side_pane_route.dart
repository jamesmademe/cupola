import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A route that holds a place in the stack for something drawn beside it.
///
/// On a tablet a title opens beside the page it was opened from. The
/// title keeps its location, the same URL the phone pushes, so it keeps its
/// place in the navigator too: this route is that place. It draws nothing,
/// lets every touch through to the page under it, and leaves that page
/// painted, so the page goes on being the list it was. The shell draws the
/// title in the pane beside the navigator, from the location
/// (`MediaSplitLayout`).
///
/// Back pops it like any route, which closes the pane; two of them in a row
/// are the pane's own history.
class SidePaneSlotPage extends Page<void> {
  const SidePaneSlotPage({
    required super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  @override
  Route<void> createRoute(BuildContext context) => SidePaneSlotRoute._(this);
}

/// The route a [SidePaneSlotPage] creates.
class SidePaneSlotRoute extends PageRoute<void> {
  // Never takes focus: the empty slot would hold the keyboard while the page
  // and the pane it stands for are what the user reads.
  SidePaneSlotRoute._(SidePaneSlotPage page)
    : super(settings: page, requestFocus: false);

  Route<dynamic>? _previous;

  /// The page this slot stands beside: the first route under it that is not
  /// a slot.
  Route<dynamic>? get host => switch (_previous) {
    final SidePaneSlotRoute slot => slot.host,
    final route => route,
  };

  /// Whether the pane has a title to go back to: the route under this one is
  /// a slot too.
  bool get hasHistory => _previous is SidePaneSlotRoute;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  // The page under it must not slide away as a pushed page would: it stays
  // where it is, the list beside the pane.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => false;

  // A modal barrier would swallow every touch meant for the page under the
  // slot, and its BlockSemantics would hide that page from a screen reader.
  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const _EdgeGuard();

  @override
  void install() {
    super.install();
    SidePaneSlots.instance._add(this);
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _previous = previousRoute;
    SidePaneSlots.instance._changed();
  }

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    SidePaneSlots.instance._changed();
  }

  @override
  void dispose() {
    SidePaneSlots.instance._remove(this);
    super.dispose();
  }
}

/// Holds the edge of the page still while a slot is over it.
///
/// The page under the slot is still a Cupertino page, and its back swipe
/// would slide it out from under the pane and then pop the slot, which is
/// the top route. The strip claims a horizontal drag starting at that edge
/// before the page's gesture can, and lets taps through.
class _EdgeGuard extends StatelessWidget {
  const _EdgeGuard();

  /// The width of the Cupertino back swipe's edge.
  static const double _edge = 20;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: SizedBox(
      width: _edge,
      height: double.infinity,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(
                HorizontalDragGestureRecognizer.new,
                (recognizer) => recognizer.onUpdate = (_) {},
              ),
        },
      ),
    ),
  );
}

/// The slots in the app's navigators, and the pages they stand beside.
///
/// A page beside a pane is on screen even though it is not the current route,
/// so [hosts] is what `watchPageActivity` asks before it pauses one.
class SidePaneSlots extends ChangeNotifier {
  SidePaneSlots._();

  static final instance = SidePaneSlots._();

  final _slots = <SidePaneSlotRoute>{};

  /// Whether [route] is on screen beside a pane: a slot standing for it is
  /// the top of its navigator.
  bool hosts(Route<dynamic> route) =>
      _slots.any((slot) => slot.isCurrent && identical(slot.host, route));

  /// Whether the pane showing [name] has a title to go back to.
  bool hasHistory(String name) => _shown(name).any((slot) => slot.hasHistory);

  /// The name of the page the pane showing [name] stands beside (its
  /// `RouteSettings.name`), or null.
  String? hostNameOf(String name) =>
      _shown(name).map((slot) => slot.host?.settings.name).nonNulls.firstOrNull;

  /// Pops the slot the pane showing [name] stands for, from its own
  /// navigator: the pane is drawn outside it, so the router cannot find that
  /// navigator from the pane's context.
  void popShown(String name) => _shown(name).firstOrNull?.navigator?.maybePop();

  /// The slots on top of their navigators that stand for [name]: a hidden
  /// branch's slot is on top of its own navigator too.
  Iterable<SidePaneSlotRoute> _shown(String name) =>
      _slots.where((slot) => slot.isCurrent && slot.settings.name == name);

  void _add(SidePaneSlotRoute slot) {
    _slots.add(slot);
    _changed();
  }

  void _remove(SidePaneSlotRoute slot) {
    if (_slots.remove(slot)) _changed();
  }

  bool _notifyScheduled = false;

  /// Tells the listeners once the frame is done: the slots change while the
  /// navigator is building, and the listeners are above it.
  void _changed() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @visibleForTesting
  int get debugCount => _slots.length;
}

/// The pane beside the navigator, as the pages under it see it.
///
/// [selected] is what the pane shows, in the shell's own terms, so a list can
/// mark the row it came from. Rebuilds its dependents when the slots change
/// too, so a page asking [hostsOf] learns it is beside the pane, or no longer
/// is.
class SidePaneScope extends InheritedNotifier<SidePaneSlots> {
  SidePaneScope({
    super.key,
    required this.selected,
    this.selectedTag,
    required this.location,
    required super.child,
  }) : super(notifier: SidePaneSlots.instance);

  /// What the pane shows, or null with no pane.
  final Object? selected;

  /// The hero tag of the tile the pane's title was opened from, if any.
  final String? selectedTag;

  /// The hero tag of the tile whose title the pane beside [context]'s page
  /// shows (`PaneSelectedMark`), or null.
  static String? selectedTagOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidePaneScope>()?.selectedTag;

  /// The router's location: the name of the slot the pane stands for, when
  /// there is a pane.
  final String location;

  /// The name of the page on screen beside the pane, or null with no pane:
  /// for a header above the navigator that hides when a page covers the one
  /// it belongs to, and must show again when that page is beside the pane.
  static String? hostNameOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SidePaneScope>();
    if (scope == null || scope.selected == null) return null;
    return scope.notifier!.hostNameOf(scope.location);
  }

  /// What the pane beside [context]'s page shows, or null.
  static Object? selectedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidePaneScope>()?.selected;

  /// Whether [context]'s page is on screen beside a pane.
  static bool hostsOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SidePaneScope>();
    if (scope == null) return false;
    final route = ModalRoute.of(context);
    return route != null && scope.notifier!.hosts(route);
  }

  @override
  bool updateShouldNotify(SidePaneScope oldWidget) =>
      selected != oldWidget.selected ||
      selectedTag != oldWidget.selectedTag ||
      location != oldWidget.location ||
      super.updateShouldNotify(oldWidget);
}
