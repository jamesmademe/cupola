import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';

/// One title on a person's page: the work, once, however many times they
/// were credited on it.
typedef PersonWork = ({MediaPreview media, int? year});

/// One trade of a person's page, `Directed` over the titles they directed,
/// newest first.
class PersonTrade {
  const PersonTrade({required this.title, required this.works});

  /// `Directed`, `Wrote`, `Acted`; for a trade outside those three, the
  /// department as TMDB names it (`Sound`).
  final String title;
  final List<PersonWork> works;

  /// How many of [works] Seerr says the server holds, whole or in part.
  int onServer({SeerrNumbering? numbering}) => works
      .where((work) => seerrHolds(work.media.mediaInfo, numbering: numbering))
      .length;
}

/// A person's credits as their page shows them: the trade they are known
/// for first, then whichever of directing, writing and acting they also did.
///
/// Read from TMDB's combined credits, which have no pages: every count on the
/// page is exact. A title they appeared in as themselves (`Self`, a talk show,
/// the news, reality television, a documentary with no part named) is no
/// part of their work and is left out; a voice role, a narration included,
/// is a role.
class PersonShelf {
  const PersonShelf._(this.trades);

  /// [knownFor] is TMDB's `knownForDepartment`, `Directing`.
  factory PersonShelf.of(PersonCombinedCredits credits, {String? knownFor}) {
    final known = knownFor?.trim() ?? '';
    final byTrade = <String, List<PersonCredit>>{
      _directed: [
        for (final credit in credits.crew)
          if (_isJob(credit, 'Director')) credit,
      ],
      _wrote: [
        for (final credit in credits.crew)
          if (credit.department == 'Writing') credit,
      ],
      _acted: [
        for (final credit in credits.cast)
          if (!_asThemselves(credit)) credit,
      ],
    };
    final lead = switch (known) {
      'Directing' => _directed,
      'Writing' => _wrote,
      'Acting' => _acted,
      '' => null,
      _ => known,
    };
    if (lead != null && !byTrade.containsKey(lead)) {
      byTrade[lead] = [
        for (final credit in credits.crew)
          if (credit.department == lead) credit,
      ];
    }
    final order = [?lead, _directed, _wrote, _acted];
    final trades = <PersonTrade>[];
    for (final title in {...order}) {
      final works = _works(byTrade[title] ?? const []);
      if (works.isNotEmpty) trades.add(PersonTrade(title: title, works: works));
    }
    return PersonShelf._(trades);
  }

  /// In page order; empty when TMDB credits them with nothing on screen.
  final List<PersonTrade> trades;

  /// The trade the page leads with, and counts in its summary.
  PersonTrade? get lead => trades.firstOrNull;

  bool get isEmpty => trades.isEmpty;

  static const _directed = 'Directed';
  static const _wrote = 'Wrote';
  static const _acted = 'Acted';

  /// TMDB's genres for a talk show, the news and reality television.
  static const _asThemselvesGenres = {10767, 10763, 10764};

  static bool _isJob(PersonCredit credit, String job) =>
      credit.job?.trim().toLowerCase() == job.toLowerCase();

  static final _self = RegExp(
    r'^\s*(self|himself|herself|themselves|themself)\b',
    caseSensitive: false,
  );

  /// TMDB's genre for a documentary: one with no part named is an
  /// appearance; one narrated is a role.
  static const _documentary = 99;

  static bool _asThemselves(PersonCredit credit) =>
      _self.hasMatch(credit.character ?? '') ||
      credit.genreIds.any(_asThemselvesGenres.contains) ||
      ((credit.character ?? '').trim().isEmpty &&
          credit.genreIds.contains(_documentary));

  /// Once per title, newest first; a title with no date yet goes last.
  static List<PersonWork> _works(List<PersonCredit> credits) {
    final seen = <String>{};
    final works = <PersonWork>[
      for (final credit in credits)
        if (seen.add('${credit.media.mediaType}:${credit.media.id}'))
          (media: credit.media, year: int.tryParse(credit.media.year)),
    ];
    works.sort((a, b) {
      final when = (b.media.releaseDate ?? '').compareTo(
        a.media.releaseDate ?? '',
      );
      if (a.year == null || b.year == null) {
        return (a.year == null ? 1 : 0) - (b.year == null ? 1 : 0);
      }
      return when;
    });
    return works;
  }

  /// What someone known for [department] does, under their name:
  /// `Director` for `Directing`. Null when TMDB does not say.
  static String? roleFor(String? department) =>
      switch (department?.trim() ?? '') {
        '' => null,
        'Acting' => 'Actor',
        'Directing' => 'Director',
        'Writing' => 'Writer',
        'Production' => 'Producer',
        'Editing' => 'Editor',
        final other => other,
      };
}
