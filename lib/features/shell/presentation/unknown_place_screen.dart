import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';

/// Where a location no route answers lands: a link from an older Cupola, a
/// widget's place that moved, a mistyped `cupola://` link. Said in the app's
/// voice with the way back Home, never the router's own error page, which
/// printed its exception to the person holding the phone.
class UnknownPlaceScreen extends StatelessWidget {
  const UnknownPlaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: AppEmptyState(
            icon: Icons.explore_off_outlined,
            title: "This page isn't in Cupola",
            message: 'The link may come from an older version of the app.',
            action: FilledButton(
              onPressed: () => context.go(ServiceRoutes.home),
              child: const Text('Go to Home'),
            ),
          ),
        ),
      ),
    );
  }
}
