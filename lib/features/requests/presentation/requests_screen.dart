import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_list.dart';

/// The requester's third tab: the requests she made.
///
/// For now the list Seerr's requests have always had, read with her own
/// session (Seerr answers an account with its own requests only) and gated by
/// what the account may do. Her own page, with the state and the time of each
/// and Cancel request on those still waiting, replaces it with her Home.
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AmbientScaffold(
      appBar: GlassAppBar(title: Text('Requests')),
      body: RequestsList(),
    );
  }
}
