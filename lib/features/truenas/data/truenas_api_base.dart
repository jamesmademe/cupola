import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';

/// Shared helpers for the domain-grouped TrueNAS API classes. Each API wraps
/// the single shared [TrueNasWsClient]; the connection is opened lazily and
/// reused across all of them.
abstract class TrueNasApiBase {
  final TrueNasWsClient client;
  const TrueNasApiBase(this.client);

  /// Queries a collection method and maps each row through [fromJson].
  Future<List<T>> queryList<T>(
    String method,
    T Function(Map<String, dynamic>) fromJson, [
    List<dynamic> params = const [],
  ]) async {
    final result = await client.call(method, params);
    return jsonObjects(result, fromJson);
  }

  /// Queries a collection method and keeps the rows as raw maps, for the
  /// screens that read a handful of keys and have no model of their own.
  Future<List<Map<String, dynamic>>> queryRawList(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    final result = await client.call(method, params);
    return jsonObjects(result, (row) => row);
  }

  /// Queries a collection method expected to match at most one row (a
  /// `[['<field>', '=', value]]` filter) and maps it, or null when nothing
  /// matched.
  Future<T?> queryFirst<T>(
    String method,
    T Function(Map<String, dynamic>) fromJson,
    List<dynamic> params,
  ) async {
    final rows = await queryRawList(method, params);
    return rows.isEmpty ? null : fromJson(rows.first);
  }

  /// Fetches a single config object and maps it, or throws if the shape is
  /// unexpected.
  Future<T> fetchObject<T>(
    String method,
    T Function(Map<String, dynamic>) fromJson, [
    List<dynamic> params = const [],
  ]) async {
    final result = await client.call(method, params);
    final map = mapOrNull(result);
    if (map == null) {
      throw TrueNasException('Unexpected $method response');
    }
    return fromJson(map);
  }
}
