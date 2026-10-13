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
///  * every source failed: the figure reads `—` ([coveredFigure]);
///  * some failed: the figure is the total over the rest, and the line under
///    it names what is not in it ([coverageNote]);
///  * one answered with only part of itself ([SourceCoverage.cutShort]: a
///    queue walk that stopped on a full page with no total, a history page
///    that came back full), the figure is a floor, `200+`, and there is
///    nobody to name;
///  * none failed: the figure is the total.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// One source a merge reads: a service, and which of its connections.
///
/// A merge reads every connection of a service, and two Radarr are two
/// sources: one can answer while the other does not, and the figure is then
/// the one that answered, with the other named under it. Keyed on the service
/// alone, the second Radarr's silence took the first one's answer out of the
/// total too, and a region fed by Radarr only read `—` over a Radarr that had
/// answered.
///
/// Equal by service and connection. [name] is how a sentence calls it and is
/// not part of its identity.
@immutable
class CoverageSource {
  const CoverageSource(this.service, {this.instanceId = '', this.name});

  final ServiceKey service;

  /// The connection read, or empty for a read of the service as a whole: a
  /// source with one connection, or one that has not been resolved to one.
  final String instanceId;

  /// What tells this connection apart from the service's others, by the
  /// app's one rule (`SettingsModel.connectionName`), or null when the
  /// service has only the one.
  final String? name;

  /// How a sentence names it: `Radarr`, `Radarr 4K`, `Radarr 2`. Joined with
  /// a space rather than ` · `, because it is listed with commas inside lines
  /// that already use ` · ` between their clauses.
  String get title => serviceWithConnection(service, name, joiner: ' ');

  @override
  bool operator ==(Object other) =>
      other is CoverageSource &&
      other.service == service &&
      other.instanceId == instanceId;

  @override
  int get hashCode => Object.hash(service, instanceId);

  @override
  String toString() =>
      'CoverageSource(${service.name}${instanceId.isEmpty ? '' : '/$instanceId'})';
}

/// The answer of each source a merge read, by connection.
@immutable
class SourceCoverage {
  const SourceCoverage({
    this.answered = const <CoverageSource>{},
    this.failed = const <CoverageSource, ServiceFailureReason>{},
    this.pending = const <CoverageSource>{},
    this.cutShort = const <CoverageSource>{},
    this.gateways = const <CoverageSource, AccessGatewayAnswer>{},
  });

  /// No source at all: nothing configured feeds the merge.
  static const none = SourceCoverage();

  /// [service] answered the read: with only part of what it holds when
  /// [cutShort], which takes the figure to a floor. [instanceId] and [name]
  /// say which connection, for a service with more than one.
  factory SourceCoverage.answeredBy(
    ServiceKey service, {
    bool cutShort = false,
    String instanceId = '',
    String? name,
  }) {
    final source = CoverageSource(service, instanceId: instanceId, name: name);
    return SourceCoverage(
      answered: {source},
      cutShort: cutShort ? {source} : const {},
    );
  }

  /// [service]'s read failed with [error], classified once here so every
  /// surface that names it says the same words.
  SourceCoverage.failure(
    ServiceKey service,
    Object? error, {
    String instanceId = '',
    String? name,
  }) : this(
         failed: {
           CoverageSource(service, instanceId: instanceId, name: name):
               classifyConnectionFailure(error),
         },
         gateways: {
           CoverageSource(service, instanceId: instanceId, name: name):
               ?accessGatewayOf(error),
         },
       );

  /// [services] have been asked and have not said anything yet.
  SourceCoverage.pendingOf(Iterable<ServiceKey> services)
    : this(pending: {for (final service in services) CoverageSource(service)});

  /// The coverage of several reads taken together.
  ///
  /// A connection read more than once (Radarr's queue and Radarr's history)
  /// is only answered when every one of its reads answered: one that failed
  /// takes its share out of the total, and one still out has not finished
  /// saying. Failed outranks pending, which outranks answered. Two connections
  /// of one service are two sources, and each keeps its own answer.
  factory SourceCoverage.merge(Iterable<SourceCoverage> parts) {
    final failed = <CoverageSource, ServiceFailureReason>{};
    final pending = <CoverageSource>{};
    final answered = <CoverageSource>{};
    final cutShort = <CoverageSource>{};
    final gateways = <CoverageSource, AccessGatewayAnswer>{};
    for (final part in parts) {
      failed.addAll(part.failed);
      gateways.addAll(part.gateways);
      pending.addAll(part.pending);
      answered.addAll(part.answered);
      cutShort.addAll(part.cutShort);
    }
    pending.removeAll(failed.keys);
    answered
      ..removeAll(failed.keys)
      ..removeAll(pending);
    cutShort.retainAll(answered);
    return SourceCoverage(
      answered: answered,
      failed: failed,
      pending: pending,
      cutShort: cutShort,
      gateways: {
        for (final MapEntry(:key, :value) in gateways.entries)
          if (failed[key] == ServiceFailureReason.accessGateway) key: value,
      },
    );
  }

  final Set<CoverageSource> answered;

  /// Sources that answered with only part of what they hold: a queue walk
  /// that stopped on a full page with no total to say whether another
  /// followed, or a history page that came back full. Always a subset of
  /// [answered]. Their share of a figure is what
  /// arrived, so the figure is a floor ([isFloor]); nothing is missing to name.
  final Set<CoverageSource> cutShort;

  /// The figure counts at least this much and maybe more: `200+`, never
  /// `200`. Only for a source that answered short; a source that failed is
  /// named under the figure instead ([coverageNote]).
  bool get isFloor => cutShort.isNotEmpty && !everySourceFailed;

  /// Each source whose read failed, with why.
  final Map<CoverageSource, ServiceFailureReason> failed;

  /// What answered in front of each failed source a gateway answered for, so
  /// its words name it.
  final Map<CoverageSource, AccessGatewayAnswer> gateways;

  /// Sources still being asked: neither a figure nor a failure yet.
  final Set<CoverageSource> pending;

  /// The services with a source that failed, for a Retry that asks them
  /// again.
  Set<ServiceKey> get failedServices => {
    for (final source in failed.keys) source.service,
  };

  /// Every source answered, and with all of itself: the figure is the whole.
  bool get isWhole => failed.isEmpty && pending.isEmpty && cutShort.isEmpty;

  /// Some answered and some failed: the figure is a part, and has to say so.
  bool get isPartial => answered.isNotEmpty && failed.isNotEmpty;

  /// Every source has been asked and none answered: there is no figure.
  bool get everySourceFailed =>
      answered.isEmpty && pending.isEmpty && failed.isNotEmpty;

  /// Whether any failed source did not answer at all: the one failure red is
  /// spent on. A line naming several takes red when one of them is silent.
  bool get anyDidNotAnswer => failed.values.any(failureDidNotAnswer);

  /// The failed sources in registry order, and a service's connections in the
  /// order they were read, so the same outage names its sources in the same
  /// order on every region.
  List<CoverageSource> get failedInOrder {
    final keys = failed.keys.toList(growable: false);
    final indexed = [
      for (var i = 0; i < keys.length; i++) (index: i, source: keys[i]),
    ];
    indexed.sort((a, b) {
      final byService = a.source.service.index.compareTo(
        b.source.service.index,
      );
      return byService != 0 ? byService : a.index.compareTo(b.index);
    });
    return [for (final entry in indexed) entry.source];
  }
}

/// [count] as a figure over [coverage]: the number, `—` when no source
/// answered, and a floor (`200+`) when one answered with only part of itself.
/// Never `0` for a count nobody was able to take, and never a row count stated
/// as the total of a queue the walk did not finish.
String coveredFigure(int count, SourceCoverage coverage) {
  if (coverage.everySourceFailed) return Lexicon.noFigure;
  return coverage.isFloor ? Lexicon.floor(count) : '$count';
}

/// A `— downloading` figure phrase as a screen reader should say it.
///
/// The dash is a glyph the eye reads as "no figure" and the ear hears as "em
/// dash" or nothing at all, so the spoken form says it: `downloading, count
/// unavailable`. A floor leading the phrase says what it is, `at least 200
/// downloading`, where a screen reader says "200 plus" or drops the mark. A
/// phrase with a plain number in it is left alone.
String spokenCountPhrase(String phrase) {
  const lead = '${Lexicon.noFigure} ';
  if (phrase.startsWith(lead)) {
    return '${phrase.substring(lead.length)}, count unavailable';
  }
  final space = phrase.indexOf(' ');
  final figure = space < 0 ? phrase : phrase.substring(0, space);
  final spoken = Lexicon.spokenFigure(figure);
  if (spoken == figure) return phrase;
  return space < 0 ? spoken : '$spoken${phrase.substring(space)}';
}

/// The line under a total that leaves a source out: `Not in the total:
/// Lidarr, SABnzbd, qBittorrent`, or null when nothing is missing, or when
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
  for (final source in coverage.failedInOrder) {
    final reason = coverage.failed[source]!;
    if (failureDidNotAnswer(reason)) {
      silent.add(source.title);
      continue;
    }
    final label = describeFailure(
      source.service,
      reason,
      gateway: coverage.gateways[source],
    ).label;
    (groups[label] ??= []).add(source.title);
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
/// anything it would have shown: `Radarr and Sonarr did not answer.` And for
/// one that answered with a refusal, its own fault sentence: `qBittorrent
/// answered but refused the sign-in.`
///
/// The sources that did not answer share the alert band's sentence so the two
/// never disagree about the same fact. The sources that failed the same way
/// share one sentence too, named as the silent ones are: `Radarr, Sonarr and
/// 6 others were reached but did not reply in time.`, never that sentence
/// once for each of them.
String coverageFailureSentence(SourceCoverage coverage) {
  final silent = <String>[];
  // In the order the first of each kind failed; keyed on what the sentence
  // says: the credential only where it is named, so two refused keys group
  // and a key and a sign-in refused do not, while a slow Plex and a slow
  // Jellyfin are one sentence.
  final faults = <(ServiceFailureReason, String), List<CoverageSource>>{};
  for (final source in coverage.failedInOrder) {
    final reason = coverage.failed[source]!;
    if (failureDidNotAnswer(reason)) {
      silent.add(source.title);
    } else {
      final credential = reason == ServiceFailureReason.unauthorized
          ? refusedCredentialOf(source.service)
          : kRefusedCredential;
      (faults[(reason, credential)] ??= []).add(source);
    }
  }
  return [
    if (silent.isNotEmpty) servicesSectionOfflineMessage(silent),
    for (final MapEntry(key: (reason, credential), value: sources)
        in faults.entries)
      ..._faultSentences(coverage, reason, credential, sources),
  ].join(' ');
}

/// One sentence for [sources] that failed for [reason] alike, or one each
/// where that sentence cannot be said of many.
List<String> _faultSentences(
  SourceCoverage coverage,
  ServiceFailureReason reason,
  String credential,
  List<CoverageSource> sources,
) {
  if (sources.length > 1) {
    final grouped = failureGroupHeadline(
      reason,
      subjects: servicesNamed([
        for (final source in sources) source.title,
      ], maxNamed: _namesPerKind),
      credential: credential,
    );
    if (grouped != null) return ['$grouped.'];
  }
  return [
    for (final source in sources)
      '${describeFailure(source.service, reason, subject: source.title, gateway: coverage.gateways[source]).headline}.',
  ];
}
