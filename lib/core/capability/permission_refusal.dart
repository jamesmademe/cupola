import 'package:dio/dio.dart';

/// An exception that knows whether it was a **permission refusal on an
/// authenticated call** — the credential worked and the service declined this
/// particular change — as opposed to a bad password or a dead token.
///
/// Deliberately not `ServiceFailureReason.unauthorized`. The connection tests
/// fold 401 and 403 together, which is right for "does this connect" and wrong
/// here: a mistyped password must never dim a page, and a refusal must never
/// be reported as a broken login.
abstract interface class HasPermissionRefusal {
  bool get isPermissionRefusal;
}

/// Whether [error] is a service saying "this credential may not do that".
///
/// The only signal a probe cannot fake: the service answering the question
/// itself. Every capability-aware action runner asks this in its `catch`.
bool isPermissionRefusal(Object error) => switch (error) {
  HasPermissionRefusal(:final isPermissionRefusal) => isPermissionRefusal,
  // Any `ApiClient` write rides a raw Dio and surfaces its exception as is.
  DioException(response: Response(statusCode: 403)) => true,
  _ => false,
};
