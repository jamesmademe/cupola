import 'package:flutter/material.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';

/// What the request control says for a title, wherever it is drawn: its
/// label and glyph, why it does not act when it does not, and what a request
/// would add when that needs saying.
class SeerrRequestWords {
  const SeerrRequestWords({
    required this.label,
    required this.icon,
    this.reason,
    this.adds,
  });

  final String label;
  final IconData icon;

  /// Why nothing is offered: the request stands, or it cannot be made. Null
  /// when a request can be sent.
  final String? reason;

  /// What a request would add, when not the whole title: the seasons not
  /// asked for yet, or the 4K copy alone.
  final String? adds;

  bool get open => reason == null;
}

/// The words of the request control over [gate].
///
/// Seerr's own state, and nothing else: "Requested" is the wrong word for a
/// title already on disk, and a disabled button with no explanation is a
/// dead end. [namesSeerr] and [namesArr] are whether the reader may read
/// those names (the requester reads neither); [arrName] names the arr.
SeerrRequestWords seerrRequestWords(
  SeerrRequestGate gate, {
  required bool namesSeerr,
  required bool namesArr,
  required String arrName,
}) {
  final missing = gate.missingSeasons;
  // Open for the 4K copy alone: the standard one is on disk or asked for
  // already, so a request now asks for 4K.
  final only4k = gate.copies == SeerrRequestCopies.uhd;
  final adds = missing.isEmpty
      ? (only4k ? 'Only the 4K copy can be requested.' : null)
      : '${missing.length == 1 ? 'Season' : 'Seasons'} '
            '${Lexicon.names(missing.map((season) => '$season'))} '
            '${missing.length == 1 ? 'is' : 'are'} not requested '
            '${only4k ? 'in 4K ' : ''}yet.';
  return switch (gate.state) {
    // The requester's badge says `On the server`: the control says the same,
    // never the operator's `Available`.
    SeerrRequestState.available => SeerrRequestWords(
      label: namesSeerr ? 'Available' : Lexicon.onTheServer,
      icon: Icons.check_circle_outline_rounded,
      reason: namesSeerr
          ? 'Already in your library, nothing to request.'
          : Lexicon.alreadyOnTheServer,
    ),
    SeerrRequestState.waitingForApproval => SeerrRequestWords(
      label: 'Requested',
      icon: Icons.check_circle_outline_rounded,
      reason: namesSeerr
          ? 'Waiting for approval in Seerr.'
          : Lexicon.requestWaiting,
    ),
    SeerrRequestState.onItsWay => SeerrRequestWords(
      label: 'Requested',
      icon: Icons.check_circle_outline_rounded,
      reason: namesArr
          ? '$arrName is already tracking this.'
          : Lexicon.onItsWay,
    ),
    // Seerr takes no second request while this one stands.
    SeerrRequestState.failed => SeerrRequestWords(
      label: namesSeerr ? 'Request failed' : Lexicon.requestDidNotGoThrough,
      icon: Icons.error_outline_rounded,
      reason: namesSeerr && namesArr
          ? 'Seerr could not send the last request to $arrName.'
          : Lexicon.lastRequestFailed,
    ),
    // The operator's own choice, made in Seerr: neutral, nothing to fix here.
    SeerrRequestState.blocklisted => SeerrRequestWords(
      label: namesSeerr
          ? StateWord.blocklisted.label
          : Lexicon.cannotBeRequested,
      icon: Icons.block_rounded,
      reason: namesSeerr
          ? 'Blocklisted in Seerr, which takes no request for it.'
          : Lexicon.blockedByOwner,
    ),
    SeerrRequestState.open => SeerrRequestWords(
      label: 'Request',
      icon: Icons.add_circle_outline_rounded,
      adds: adds,
    ),
  };
}
