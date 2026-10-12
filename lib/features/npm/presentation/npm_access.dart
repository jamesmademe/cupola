import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';

/// `GET /api/users/me`, once per connection.
///
/// Null on any failure. The failure is not rethrown because this provider is
/// not a screen's data: it is the source of the gate in front of the screen's
/// controls (`probeNpmCapability`) and of the audit log's admin-only note, and
/// a source that throws would replace the page with an error over a question
/// the page does not otherwise need answered.
final npmAccountProvider = FutureProvider<NpmAccount?>((ref) async {
  try {
    return await ref.watch(npmClientProvider).currentUser();
  } catch (_) {
    return null;
  }
});
