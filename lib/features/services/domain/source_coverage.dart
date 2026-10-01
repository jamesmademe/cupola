/// Which of the sources behind a merged Dashboard figure answered.
///
/// ## Why a merge has to say this
///
/// Every merged region on the Dashboard reads several services and degrades a
/// failed one to nothing, so that one dark client cannot take the region down.
/// The rows survive that rule; the figure above them does not. `0 downloading`
/// over download clients that did not answer is not a count of anything, and
/// `3 downloading` with SABnzbd dark reads as the whole queue when it is the
/// queue minus SABnzbd's share. A count asserts a fact, and it can only assert
/// one about the sources that answered.
///
/// So a merge hands back, with its value, which of its configured sources
/// answered, which failed and why, and which have not said yet. The figure
/// rule follows from that and nothing else:
///
///  * every source failed — the figure reads `—` ([coveredFigure]);
///  * some failed — the figure is the total over the rest, and the line under
///    it names what is not in it ([coverageNote]);
///  * none failed — the figure is the total.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The answer of each source a merge read, by service.
@immutable
class SourceCoverage {
  const SourceCoverage({
    this.answered = const <ServiceKey>{},
    this.failed = const <ServiceKey, ServiceFailureReason>{},
    this.pending = const <ServiceKey>{},
  });

  /// No source at all: nothing configured feeds the merge.
  static const none = SourceCoverage();

  /// [service] answered the read.
  SourceCoverage.answeredBy(ServiceKey service) : this(answered: {service});

  /// [service]'s read failed with [error], classified once here so every
  /// surface that names it says the same words.
  SourceCoverage.failure(ServiceKey service, Object? error)
    : this(failed: {service: classifyConnectionFailure(error)});

  /// [services] have been asked and have not said anything yet.
  SourceCoverage.pendingOf(Iterable<ServiceKey> services)
    : this(pending: services.toSet());

  /// The coverage of several reads taken together.
  ///
  /// A service read more than once — Radarr's queue and Radarr's history — is
  /// only answered when every one of its reads answered: one that failed takes
  /// its share out of the total, and one still out has not finished saying.
  /// Failed outranks pending, which outranks answered.
  factory SourceCoverage.merge(Iterable<SourceCoverage> parts) {
    final failed = <ServiceKey, ServiceFailureReason>{};
    final pending = <ServiceKey>{};
    final answered = <ServiceKey>{};
    for (final part in parts) {
      failed.addAll(part.failed);
      pending.addAll(part.pending);
      answered.addAll(part.answered);
    }
    pending.removeAll(failed.keys);
    answered
      ..removeAll(failed.keys)
      ..removeAll(pending);
    return SourceCoverage(answered: answered, failed: failed, pending: pending);
  }

  final Set<ServiceKey> answered;

  /// Each source whose read failed, with why.
  final Map<ServiceKey, ServiceFailureReason> failed;

  /// Sources still being asked: neither a figure nor a failure yet.
  final Set<ServiceKey> pending;

  /// Every source answered: the figure is the whole.
  bool get isWhole => failed.isEmpty && pending.isEmpty;

  /// Some answered and some failed: the figure is a part, and has to say so.
  bool get isPartial => answered.isNotEmpty && failed.isNotEmpty;

  /// Every source has been asked and none answered: there is no figure.
  bool get everySourceFailed =>
      answered.isEmpty && pending.isEmpty && failed.isNotEmpty;

  /// Whether any failed source did not answer at all — the one failure red is
  /// spent on. A line naming several takes red when one of them is silent.
  bool get anyDidNotAnswer => failed.values.any(failureDidNotAnswer);

  /// The failed sources in registry order, so the same outage names its
  /// services in the same order on every region.
  List<ServiceKey> get failedInOrder =>
      failed.keys.toList(growable: false)
        ..sort((a, b) => a.index.compareTo(b.index));
}

/// [count] as a figure over [coverage]: the number, or `—` when no source
/// answered. Never `0` for a count nobody was able to take.
String coveredFigure(int count, SourceCoverage coverage) =>
    coverage.everySourceFailed ? Lexicon.noFigure : '$count';

/// A `— downloading` figure phrase as a screen reader should say it.
///
/// The dash is a glyph the eye reads as "no figure" and the ear hears as "em
/// dash" or nothing at all, so the spoken form says it: `downloading, count
/// unavailable`. A phrase with a number in it is left alone.
String spokenCountPhrase(String phrase) {
  const lead = '${Lexicon.noFigure} ';
  if (!phrase.startsWith(lead)) return phrase;
  return '${phrase.substring(lead.length)}, count unavailable';
}

/// The line under a total that leaves a source out: `Not in the total:
/// Lidarr, SABnzbd, qBittorrent`, or null when nothing is missing — or when
/// nothing answered, which has no total to qualify and says
/// [coverageFailureSentence] instead.
///
/// Names only. Who did not answer and why is the alert band's sentence at the
/// top of the page, and the note used to say it again under every figure it
/// qualified (`Lidarr and SABnzbd did not answer · qBittorrent refused the
/// sign-in · not in the total`), long enough that a phone cut it off before
/// the part that mattered here. Every failed source is named, silent or
/// refusing alike, silence first because it is the red half, and the same
/// cap holds: at most two of each kind of failure, the rest counted. The
/// glyph still says which kind leads ([SourceCoverage.anyDidNotAnswer]).
String? coverageNote(SourceCoverage coverage) {
  if (!coverage.isPartial) return null;
  final groups = <String, List<String>>{};
  final silent = <String>[];
  for (final service in coverage.failedInOrder) {
    final reason = coverage.failed[service]!;
    if (failureDidNotAnswer(reason)) {
      silent.add(service.title);
      continue;
    }
    final label = describeFailure(service, reason).label;
    (groups[label] ??= []).add(service.title);
  }
  final named = <String>[];
  var hidden = 0;
  for (final titles in [silent, ...groups.values]) {
    named.addAll(titles.take(_namesPerKind));
    if (titles.length > _namesPerKind) hidden += titles.length - _namesPerKind;
  }
  final names = named.join(', ');
  return hidden == 0
      ? 'Not in the total: $names'
      : 'Not in the total: $names and ${hidden == 1 ? '1 other' : '$hidden others'}';
}

/// How many sources of one kind of failure a note names before it counts the
/// rest.
const _namesPerKind = 2;

/// What a region says when every one of its sources failed, in place of
/// anything it would have shown: `Radarr and Sonarr did not answer.` — and,
/// for one that answered with a refusal, its own fault sentence: `qBittorrent
/// answered but refused the sign-in.`
///
/// The sources that did not answer share the alert band's sentence so the two
/// never disagree about the same fact.
String coverageFailureSentence(SourceCoverage coverage) {
  final silent = <String>[];
  final faults = <String>[];
  for (final service in coverage.failedInOrder) {
    final reason = coverage.failed[service]!;
    if (failureDidNotAnswer(reason)) {
      silent.add(service.title);
    } else {
      faults.add('${describeFailure(service, reason).headline}.');
    }
  }
  return [
    if (silent.isNotEmpty) servicesSectionOfflineMessage(silent),
    ...faults,
  ].join(' ');
}
