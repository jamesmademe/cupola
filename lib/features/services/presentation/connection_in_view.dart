import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The connection a link names (`?i=`): [requested] when it is a configured
/// connection of [service], and empty otherwise.
///
/// Empty is the service's active connection (the lens): an old link, a deep
/// link, a page opened from somewhere that does not know a connection. A value
/// that names no connection of [service] (removed since the link was made, or
/// another service's, or blank), or one with no address yet, is empty too, so
/// a stale link opens on the active connection rather than on an error about
/// a connection that no longer exists or cannot be asked.
String namedConnectionOf(
  SettingsModel settings,
  ServiceKey service,
  String? requested,
) {
  final id = requested?.trim() ?? '';
  if (id.isEmpty) return '';
  final instance = settings.instanceById(id);
  return instance != null &&
          instance.service == service &&
          instance.isConfigured
      ? id
      : '';
}

/// The connection one visit to a service reads, and the way to change it.
///
/// A visit is one stay inside a service's own pages: from the moment its shell
/// page is pushed to the moment that page is popped or replaced. What it reads
/// is [instanceId] while that is not empty, and the service's lens otherwise.
/// It is read by everything under [ConnectionInViewScope]: the header's lens
/// badge, every tab, a library, an item.
@immutable
class ConnectionInView {
  const ConnectionInView._(this.service, this.instanceId, this._show);

  final ServiceKey service;

  /// The connection in view; empty when the visit has none and reads the
  /// lens.
  final String instanceId;

  final void Function(String instanceId) _show;

  /// Puts [instanceId] in view for the rest of the visit: the lens sheet's
  /// choice. The lens itself is the sheet's to move.
  void show(String instanceId) => _show(instanceId);

  /// What [context] is reading for [service]: the visit's connection, or null
  /// when the page is not under a visit to that service (every other service,
  /// and a screen built outside the router).
  ///
  /// [listen] false for an event handler or a fetch, which must not register a
  /// dependency.
  static ConnectionInView? maybeOf(
    BuildContext context,
    ServiceKey service, {
    bool listen = true,
  }) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<_InViewScope>()
        : context.getInheritedWidgetOfExactType<_InViewScope>();
    final view = scope?.view;
    return view != null && view.service == service ? view : null;
  }
}

/// Holds the connection in view for one visit to a media server, under the
/// service's shell page.
///
/// **In the shell, not in a provider.** The state lives and dies with the
/// shell's page: leaving the service (popping or replacing the page) ends the
/// visit, and nothing is left in a global store to be read by the next one. A
/// provider keyed on the service would outlive the visit and have to be reset
/// by something that notices it ended.
///
/// **What it remembers.** The location the router shows is passed in
/// ([location]) every time anything inside the service navigates, and the last
/// valid `?i=` it carried is the connection in view: opening a media server
/// from a row that names a connection (Home's Now playing, a library tile)
/// reads that connection on every tab until the visit ends, and a location
/// with no `?i=` (a tab's root, reached by the tab bar) keeps what is in view.
/// Opening it never moves the lens.
///
/// **A restored location is not a new link.** `goBranch` puts a tab back where
/// the user left it, query included, so a tab opened with `?i=` replays that
/// `?i=` when it is switched back to. If the replay were read as a link it
/// would take the visit back to the connection the user had since moved away
/// from in the lens sheet. A location is read only when the `?i=` it carries
/// differs from the one the same path carried the last time it was shown.
class ConnectionInViewScope extends ConsumerStatefulWidget {
  const ConnectionInViewScope({
    super.key,
    required this.service,
    required this.location,
    required this.child,
  });

  final ServiceKey service;

  /// The location the router is showing inside [service].
  final Uri location;

  final Widget child;

  @override
  ConsumerState<ConnectionInViewScope> createState() =>
      _ConnectionInViewScopeState();
}

class _ConnectionInViewScopeState extends ConsumerState<ConnectionInViewScope> {
  /// The connection in view, as last asked for; empty reads the lens. Checked
  /// against the settings again each build, so a connection removed meanwhile
  /// reads as the lens.
  String _inView = '';

  /// What `?i=` each path carried the last time it was shown, empty for none.
  final Map<String, String> _lastOn = {};

  @override
  void initState() {
    super.initState();
    _see(widget.location);
  }

  @override
  void didUpdateWidget(ConnectionInViewScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _see(widget.location);
  }

  void _see(Uri location) {
    final asked = location.queryParameters['i']?.trim() ?? '';
    final before = _lastOn[location.path];
    _lastOn[location.path] = asked;
    if (asked.isEmpty || asked == before) return;
    final named = namedConnectionOf(
      ref.read(currentSettingsProvider),
      widget.service,
      asked,
    );
    if (named.isNotEmpty) _inView = named;
  }

  void _show(String instanceId) {
    if (!mounted) return;
    setState(() => _inView = instanceId);
  }

  @override
  Widget build(BuildContext context) {
    final shown = namedConnectionOf(
      ref.watch(currentSettingsProvider),
      widget.service,
      _inView,
    );
    return _InViewScope(
      view: ConnectionInView._(widget.service, shown, _show),
      child: widget.child,
    );
  }
}

class _InViewScope extends InheritedWidget {
  const _InViewScope({required this.view, required super.child});

  final ConnectionInView view;

  @override
  bool updateShouldNotify(_InViewScope oldWidget) =>
      view.service != oldWidget.view.service ||
      view.instanceId != oldWidget.view.instanceId;
}
