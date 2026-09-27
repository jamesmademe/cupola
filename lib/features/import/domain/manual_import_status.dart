import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The four classes the Review screen sorts a scan into.
///
/// One taxonomy, named once, because three things have to agree on it: the
/// counts in the filter row, which rows the list builds, and what a filter chip
/// hides. While each of those carried its own booleans, "hide the imported
/// ones" lived in the app bar and "collapse the other ones" lived in a section
/// header — two controls, two mental models, for one question: what am I
/// looking at?
enum ManualImportFacet { ready, attention, imported, other }

/// The count of one facet, resolved into the closed status vocabulary.
///
/// The chip renders this; it never derives a tone from the facet itself.
MediaStatusInfo manualImportFacetStatus(ManualImportFacet facet, int count) {
  return switch (facet) {
    ManualImportFacet.ready => MediaStatusInfo(
      availability: MediaAvailability.available,
      labelOverride: '$count ready',
      toneOverride: StatusTone.success,
    ),
    ManualImportFacet.attention => MediaStatusInfo(
      labelOverride: count == 1 ? '1 needs a match' : '$count need a match',
      toneOverride: StatusTone.warning,
    ),
    ManualImportFacet.imported => MediaStatusInfo(
      availability: MediaAvailability.available,
      labelOverride: '$count imported',
      toneOverride: StatusTone.neutral,
    ),
    ManualImportFacet.other => MediaStatusInfo(
      labelOverride: '$count other',
      toneOverride: StatusTone.neutral,
    ),
  };
}

/// The same count as one spoken phrase.
///
/// The painted chip is a fragment sized for a pill — "1 needs a match", "3
/// imported" — and read out verbatim it produces "1 needs a match files". A
/// screen reader gets the sentence instead; the eye keeps the fragment.
String manualImportFacetSpokenLabel(ManualImportFacet facet, int count) {
  final files = count == 1 ? '1 file' : '$count files';
  return switch (facet) {
    ManualImportFacet.ready => '$files ready to import',
    ManualImportFacet.attention =>
      '$files ${count == 1 ? 'needs' : 'need'} a match',
    ManualImportFacet.imported => '$files already in the library',
    ManualImportFacet.other => '$files of a kind this service cannot import',
  };
}

/// Resolves a scanned file's import state into the closed status vocabulary.
///
/// Lives in `domain/` per the Closed Tone Rule: the Review screen renders
/// whatever arrives here and never re-derives a tone. Five states cover the
/// whole surface:
///
/// - **Imported** (neutral, on disk): the service already has this file. Not an
///   error and not a problem — but the row is still a control, because the user
///   may want it taken again.
/// - **Re-import** (info): an imported file the user ticked to send anyway.
///   [reimportSelected] is what distinguishes it, and it is a distinct status
///   rather than a selected-looking "Imported" because the consequence differs:
///   this file is going into the next batch.
/// - **Ready** (success): fully matched, will be included in the import. When
///   the service also reported a metadata rejection the tone escalates to
///   warning via [MediaStatusInfo.hasWarning] while the label stays honest.
/// - **Sample** (neutral): matched, and the service says it is a sample. Shown,
///   tickable, and never preselected — see [ManualImportItem.isSample].
/// - **No match** (warning): the service permanently rejected the file's
///   identity; it cannot import until the user assigns one.
/// - **Needs match** (warning): unmatched, but nothing permanent — assigning
///   an identity clears it.
MediaStatusInfo manualImportItemStatus(
  ServiceKey service,
  ManualImportItem item, {
  bool reimportSelected = false,
}) {
  if (item.isAlreadyImported) {
    if (reimportSelected) {
      // `upgradable` for the glyph as much as the state: the arrow-into-a-line
      // says "this replaces what is there", which is precisely the deal.
      return const MediaStatusInfo(
        availability: MediaAvailability.upgradable,
        labelOverride: 'Re-import',
        toneOverride: StatusTone.info,
      );
    }
    return const MediaStatusInfo(
      availability: MediaAvailability.available,
      labelOverride: 'Imported',
      toneOverride: StatusTone.neutral,
    );
  }

  if (item.isReadyForImportFor(service)) {
    // Checked before Ready, because a sample is fully matched and would
    // otherwise read "Ready" next to an unticked box — a row that contradicts
    // itself. Neutral: the file is backlog the user may still choose to take,
    // not a fault the service is reporting.
    if (item.isSample) {
      return MediaStatusInfo(
        labelOverride: 'Sample',
        toneOverride: StatusTone.neutral,
        detail: item.firstRejectionReason,
      );
    }
    return MediaStatusInfo(
      labelOverride: 'Ready',
      toneOverride: StatusTone.success,
      hasWarning: item.hasBlockingMetadataRejection,
      detail: item.hasBlockingMetadataRejection
          ? item.firstRejectionReason
          : null,
    );
  }

  if (item.hasBlockingIdentityRejection) {
    return MediaStatusInfo(
      labelOverride: 'No match',
      // Amber, not red. Red is reserved for a connection that did not answer;
      // this one answered, and what it said is that it cannot name the file —
      // a fault the user can clear by assigning an identity. It used to paint
      // red while the *same* affordance, one row below, painted amber for an
      // unmatched file with no rejection attached: two tones, one fix sheet,
      // and the facet chip above them already called the whole group warning.
      toneOverride: StatusTone.warning,
      detail: item.firstRejectionReason,
    );
  }

  return MediaStatusInfo(
    labelOverride: 'Needs match',
    toneOverride: StatusTone.warning,
    detail: item.firstRejectionReason,
  );
}

/// Resolves an \*arr `ManualImport` command's state for the Track screen.
///
/// The command is aggregate — the services do not report per-file results — so
/// this is deliberately the only status the Track screen renders as truth.
MediaStatusInfo manualImportCommandStatus(ManualImportCommandStatus command) {
  final (label, tone) = switch (command.status) {
    // Blue, not amber. A command waiting its turn is the service working as
    // designed; amber here put a fault tone on every import that arrived while
    // another one was still running.
    'queued' => ('Queued', StatusTone.info),
    'started' => ('Running', StatusTone.info),
    'completed' => ('Completed', StatusTone.success),
    // Amber, not red: the service answered and reported the import went
    // wrong, which is a fault. An aborted or orphaned command stopped without
    // anyone asking it to, which is the same arm.
    'failed' => ('Failed', StatusTone.warning),
    'aborted' => ('Aborted', StatusTone.warning),
    'orphaned' => ('Orphaned', StatusTone.warning),
    // Somebody cancelled it. Stopped on purpose is neutral.
    'cancelled' => ('Cancelled', StatusTone.neutral),
    _ => (command.status, StatusTone.info),
  };
  return MediaStatusInfo(
    labelOverride: label,
    toneOverride: tone,
    detail: command.message,
  );
}
