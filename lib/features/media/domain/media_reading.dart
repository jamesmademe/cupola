import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';

/// What one source said about a title, and when it said it.
@immutable
class MediaAnswer<T> {
  const MediaAnswer(this.value, this.at);

  final T value;

  /// When the answer arrived: the time a `Did not answer since` line names
  /// once the source stops answering (brand book, case c).
  final DateTime at;
}

/// One source's reading as a row draws it: waiting, answered, or did not
/// answer with whatever it said before.
///
/// Built from the source's `AsyncValue` ([MediaReading.of]), so a refresh that
/// fails keeps the last answer under the failure instead of emptying the row:
/// last-known data keeps full-strength ink (brand book, *Failure states*).
sealed class MediaReading<T> {
  const MediaReading();

  /// [value]'s reading: its answer, or its failure with the answer before it.
  static MediaReading<T> of<T>(AsyncValue<MediaAnswer<T>> value) {
    final last = value.value;
    if (value.hasError) {
      final error = value.error;
      return MediaReadingFailed<T>(
        classifyConnectionFailure(error),
        gateway: accessGatewayOf(error),
        lastKnown: last,
      );
    }
    if (last != null) {
      return MediaReadingAnswered<T>(last, refreshing: value.isLoading);
    }
    return MediaReadingWaiting<T>();
  }
}

/// Nothing answered yet, and nothing earlier to show: the row's skeleton.
final class MediaReadingWaiting<T> extends MediaReading<T> {
  const MediaReadingWaiting();
}

/// The source answered.
final class MediaReadingAnswered<T> extends MediaReading<T> {
  const MediaReadingAnswered(this.answer, {this.refreshing = false});

  final MediaAnswer<T> answer;

  /// A newer answer is on its way; this one stays drawn meanwhile.
  final bool refreshing;
}

/// The source did not answer (case c), or answered with a failure.
final class MediaReadingFailed<T> extends MediaReading<T> {
  const MediaReadingFailed(this.failure, {this.gateway, this.lastKnown});

  final ServiceFailureReason failure;

  /// A gateway in front of the service that answered in its place.
  final AccessGatewayAnswer? gateway;

  /// What the source said before it stopped answering, with its time.
  final MediaAnswer<T>? lastKnown;
}
