import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';

/// One kind's request limit, as `GET /api/v1/user/{id}/quota` answers it
/// (`QuotaStatus`, `server/entity/User.ts` `getQuota`).
///
/// A movie quota counts movie requests; a series quota counts **seasons**, so
/// [limit] and [used] are seasons for [SeerrMediaKind.tv].
@immutable
final class SeerrQuotaStatus {
  const SeerrQuotaStatus({
    this.days,
    this.limit,
    this.used = 0,
    this.remaining,
    this.restricted = false,
  });

  /// No limit at all: what an account without a quota, or with
  /// MANAGE_USERS, is answered.
  const SeerrQuotaStatus.unlimited() : this();

  factory SeerrQuotaStatus.fromJson(Map<String, dynamic>? json) =>
      SeerrQuotaStatus(
        days: _positive(json?['days']),
        limit: _positive(json?['limit']),
        used: intOrNull(json?['used']) ?? 0,
        remaining: intOrNull(json?['remaining']),
        restricted: boolOrFalse(json?['restricted']),
      );

  /// The window the limit counts over, in days. Null: no window, every
  /// request ever made counts.
  final int? days;

  /// The most the account may ask for in the window. Null: no limit. The
  /// server answers 0 for "no limit", and that reads as null here.
  final int? limit;

  /// How many the account has asked for in the window.
  final int used;

  /// How many are left. The server leaves it out when there is no limit.
  final int? remaining;

  /// The server's own verdict: the limit is reached, and a request of this
  /// kind would be refused.
  final bool restricted;

  @override
  bool operator ==(Object other) =>
      other is SeerrQuotaStatus &&
      other.days == days &&
      other.limit == limit &&
      other.used == used &&
      other.remaining == remaining &&
      other.restricted == restricted;

  @override
  int get hashCode => Object.hash(days, limit, used, remaining, restricted);

  @override
  String toString() =>
      'SeerrQuotaStatus(limit: $limit, days: $days, used: $used, '
      'restricted: $restricted)';
}

/// An account's request limits, both kinds.
@immutable
final class SeerrQuota {
  const SeerrQuota({
    this.movie = const SeerrQuotaStatus.unlimited(),
    this.tv = const SeerrQuotaStatus.unlimited(),
  });

  factory SeerrQuota.fromJson(Map<String, dynamic> json) => SeerrQuota(
    movie: SeerrQuotaStatus.fromJson(mapOrNull(json['movie'])),
    tv: SeerrQuotaStatus.fromJson(mapOrNull(json['tv'])),
  );

  final SeerrQuotaStatus movie;
  final SeerrQuotaStatus tv;

  SeerrQuotaStatus of(SeerrMediaKind kind) => switch (kind) {
    SeerrMediaKind.movie => movie,
    SeerrMediaKind.tv => tv,
  };

  @override
  bool operator ==(Object other) =>
      other is SeerrQuota && other.movie == movie && other.tv == tv;

  @override
  int get hashCode => Object.hash(movie, tv);

  @override
  String toString() => 'SeerrQuota(movie: $movie, tv: $tv)';
}

int? _positive(Object? value) {
  final number = intOrNull(value);
  return number == null || number <= 0 ? null : number;
}
