import 'package:flutter/material.dart';

import 'package:cupola/core/status/media_status.dart';

/// A single key metric shown in a [ServiceKpiPeek] rail.
///
/// Kept transport-agnostic: each service builds its own list of KPIs from
/// whatever data it already has loaded, so the peek stays a pure presentation
/// concern.
@immutable
class ServiceKpi {
  /// Short uppercase-friendly label (e.g. "Missing", "Down").
  final String label;

  /// Preformatted value string (e.g. "128", "2.4 MB/s", "94%").
  final String value;

  /// Small leading icon.
  final IconData icon;

  /// How this figure reads, and whether it reads at all.
  ///
  /// `null` is the resting state: an ordinary metric that nobody needs to look
  /// at, drawn in the service accent like its three neighbours. A non-null tone
  /// means the builder that computed this number decided it is the reason you
  /// would open the service — and says in the same breath *which kind* of
  /// reason, which is the part the old `Color? accent` could not carry:
  ///
  ///  * [StatusTone.neutral] — backlog. 34 films are missing. Worth surfacing,
  ///    not worth colouring; this is the normal resting state of an \*arr.
  ///  * [StatusTone.warning] — a fault. An indexer is failing, a stack exited,
  ///    a pool is at 80%.
  ///  * [StatusTone.info] — activity. Bytes are moving, someone is watching.
  ///
  /// It used to be a raw `Color?`, which conflated *noteworthy* with *amber*:
  /// every flagged metric was painted `AppColors.warning`, so a library with a
  /// backlog and a server with a dying disk were the same colour, and the tone
  /// the matrix cell showed had to be re-derived downstream by matching the
  /// label against a set of strings. Now the judgement travels with the number.
  final StatusTone? tone;

  /// Whether this figure is the reason you would look at the service.
  bool get isNoteworthy => tone != null;

  const ServiceKpi({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });
}
