import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Utility class for common routing operations.
class RouteUtils {
  /// Creates a CupertinoPage that supports iOS swipe-back gesture.
  /// This is the preferred way to enable back gesture on detail screens.
  static Page<void> cupertinoPage({
    required LocalKey key,
    required Widget child,
    String? name,
  }) {
    return CupertinoPage(key: key, name: name, child: child);
  }

  static void popOrGo(BuildContext context, String fallbackLocation) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    context.go(fallbackLocation);
  }

  /// Safely parses an integer path parameter.
  static int? safeIntParam(GoRouterState state, String paramName) {
    return int.tryParse(state.pathParameters[paramName] ?? '');
  }

  /// Safely returns a typed extra value.
  static T? safeExtra<T>(GoRouterState state) {
    final extra = state.extra;
    return extra is T ? extra : null;
  }

  /// Creates a temporary redirect page.
  static Page<void> redirectPage({
    required LocalKey key,
    required String location,
  }) {
    return CupertinoPage(
      key: key,
      child: _RedirectWidget(location: location),
    );
  }
}

class _RedirectWidget extends StatefulWidget {
  const _RedirectWidget({required this.location});

  final String location;

  @override
  State<_RedirectWidget> createState() => _RedirectWidgetState();
}

class _RedirectWidgetState extends State<_RedirectWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(widget.location);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
