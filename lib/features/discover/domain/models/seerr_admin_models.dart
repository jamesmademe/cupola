import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/media_status.dart';

enum SeerrIssueFilter {
  open('open', 'Open'),
  resolved('resolved', 'Resolved'),
  all('all', 'All');

  const SeerrIssueFilter(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// A paginated admin list together with the truth about how much of it arrived.
/// A later page can fail after the first one has rendered useful rows; callers
/// must keep those rows, but they must not present them as the complete list.
@immutable
class SeerrAdminResult<T> {
  const SeerrAdminResult({
    required this.items,
    required this.total,
    this.isPartial = false,
  });

  final List<T> items;
  final int total;
  final bool isPartial;
}

@immutable
class SeerrUser {
  const SeerrUser({
    required this.id,
    this.email,
    this.username,
    this.plexUsername,
    this.avatar,
    this.userType,
    this.permissions,
    this.requestCount,
    this.createdAt,
  });

  final int id;
  final String? email;
  final String? username;
  final String? plexUsername;
  final String? avatar;
  final int? userType;
  final int? permissions;
  final int? requestCount;
  final String? createdAt;

  factory SeerrUser.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return SeerrUser(
      id: _int(json['id']) ?? 0,
      email: _text(json['email']),
      username: _text(json['username']),
      plexUsername: _text(json['plexUsername'] ?? json['plex_username']),
      avatar: _text(json['avatar']),
      userType: _int(json['userType'] ?? json['user_type']),
      permissions: _int(json['permissions']),
      requestCount: _int(json['requestCount'] ?? json['request_count']),
      createdAt: _text(json['createdAt'] ?? json['created_at']),
    );
  }

  String get displayName {
    for (final value in [username, plexUsername, email]) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return 'Unnamed user';
  }
}

@immutable
class SeerrIssueMedia {
  const SeerrIssueMedia({
    this.id,
    this.tmdbId,
    this.title,
    this.mediaType,
    this.posterPath,
  });

  final int? id;
  final int? tmdbId;
  final String? title;
  final String? mediaType;
  final String? posterPath;

  factory SeerrIssueMedia.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return SeerrIssueMedia(
      id: _int(json['id']),
      tmdbId: _int(json['tmdbId'] ?? json['tmdb_id']),
      title: _text(json['title'] ?? json['name']),
      mediaType: _text(json['mediaType'] ?? json['media_type'] ?? json['type']),
      posterPath: _text(json['posterPath'] ?? json['poster_path']),
    );
  }
}

@immutable
class SeerrIssue {
  const SeerrIssue({
    required this.id,
    required this.issueType,
    required this.status,
    this.media,
    this.createdBy,
    this.modifiedBy,
    this.commentCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int? issueType;

  /// Overseerr's own `status`: 1 open, 2 resolved. Null when the server did
  /// not send one, which is not the same as either.
  final int? status;
  final SeerrIssueMedia? media;
  final SeerrUser? createdBy;
  final SeerrUser? modifiedBy;
  final int commentCount;
  final String? createdAt;
  final String? updatedAt;

  factory SeerrIssue.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final comments = json['comments'];
    return SeerrIssue(
      id: _int(json['id']) ?? 0,
      issueType: _int(json['issueType'] ?? json['issue_type']),
      status: _int(json['status']),
      media: json['media'] == null
          ? null
          : SeerrIssueMedia.fromJson(json['media']),
      createdBy: json['createdBy'] == null
          ? null
          : SeerrUser.fromJson(json['createdBy']),
      modifiedBy: json['modifiedBy'] == null
          ? null
          : SeerrUser.fromJson(json['modifiedBy']),
      commentCount: comments is List
          ? comments.length
          : (_int(json['commentCount']) ?? 0),
      createdAt: _text(json['createdAt'] ?? json['created_at']),
      updatedAt: _text(json['updatedAt'] ?? json['updated_at']),
    );
  }

  String get issueTypeLabel => switch (issueType) {
    1 => 'Video',
    2 => 'Audio',
    3 => 'Subtitles',
    4 => 'Other',
    _ => 'Issue',
  };

  bool get isResolved => status == 2;

  /// Whether this issue can still be resolved.
  ///
  /// A missing `status` is treated as open: the Resolve call is idempotent on
  /// Overseerr's side, so offering it on an issue that turns out to be closed
  /// costs a redundant POST, while withholding it on an open one leaves the
  /// user with no way to act.
  bool get isOpen => !isResolved;

  /// **From the record, never from the query that fetched it.** This used to
  /// read the `SeerrIssueFilter`, which meant the "All" tab painted every row
  /// amber — resolved issues included — and reported the whole list as
  /// faulting. Amber is a fault (the tone rule); a resolved issue is a
  /// completed thing and reads green.
  StatusTone get tone => isResolved ? StatusTone.success : StatusTone.warning;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
