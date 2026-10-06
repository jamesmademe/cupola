import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/person_shelf.dart';

/// A person's credits as their page shows them: by trade, the one they are
/// known for first, each title once, newest first, and nothing they did as
/// themselves.
void main() {
  Map<String, Object?> credit(
    int id,
    String title, {
    String type = 'movie',
    String? date,
    String? job,
    String? department,
    String? character,
    List<int> genres = const [],
    int? status,
  }) => {
    'id': id,
    'mediaType': type,
    if (type == 'tv') 'name': title else 'title': title,
    type == 'tv' ? 'firstAirDate' : 'releaseDate': ?date,
    'job': ?job,
    'department': ?department,
    'character': ?character,
    'genreIds': genres,
    if (status != null) 'mediaInfo': {'status': status},
  };

  test('an actor leads with what they acted in, then what they directed', () {
    final shelf = PersonShelf.of(
      PersonCombinedCredits.fromJson({
        'cast': [
          credit(1, 'Big', date: '1988-06-03', character: 'Josh'),
          credit(2, 'Toy Story', date: '1995-11-22', character: 'Woody'),
        ],
        'crew': [
          credit(
            3,
            'That Thing You Do!',
            date: '1996-10-04',
            job: 'Director',
            department: 'Directing',
          ),
          credit(
            3,
            'That Thing You Do!',
            date: '1996-10-04',
            job: 'Screenplay',
            department: 'Writing',
          ),
          credit(
            4,
            'Band of Brothers',
            type: 'tv',
            date: '2001-09-09',
            job: 'Executive Producer',
            department: 'Production',
          ),
        ],
      }),
      knownFor: 'Acting',
    );

    expect(
      [for (final t in shelf.trades) t.title],
      ['Acted', 'Directed', 'Wrote'],
    );
    // Newest first.
    expect(
      [for (final w in shelf.lead!.works) w.media.title],
      ['Toy Story', 'Big'],
    );
    // Producing is not what they are known for, and is left out.
    expect(
      shelf.trades.expand((t) => t.works).map((w) => w.media.title),
      isNot(contains('Band of Brothers')),
    );
    expect(PersonShelf.roleFor('Acting'), 'Actor');
  });

  test('an appearance as themselves is no part of their work', () {
    final shelf = PersonShelf.of(
      PersonCombinedCredits.fromJson({
        'cast': [
          credit(1, 'Cast Away', date: '2000-12-22', character: 'Chuck'),
          credit(2, 'The Tonight Show', type: 'tv', character: 'Self - Guest'),
          credit(3, 'A Documentary', date: '2010-01-01', character: 'Himself'),
          credit(4, 'Morning News', type: 'tv', character: '', genres: [10763]),
          credit(5, 'Shrek', date: '2001-05-18', character: 'Lord (voice)'),
          credit(6, 'Splits', date: '2012-01-01', character: '', genres: [99]),
          credit(
            7,
            'Voyage of Time',
            date: '2016-10-07',
            character: 'Narrator (voice)',
            genres: [99],
          ),
        ],
      }),
      knownFor: 'Acting',
    );

    expect(
      [for (final w in shelf.lead!.works) w.media.title],
      ['Voyage of Time', 'Shrek', 'Cast Away'],
    );
  });

  test('a director: the count of what is on the server is of the lead '
      'trade, and a title with no date yet goes last', () {
    final shelf = PersonShelf.of(
      PersonCombinedCredits.fromJson({
        'crew': [
          credit(1, 'Next One', job: 'Director', department: 'Directing'),
          credit(
            2,
            'Tears of Steel',
            date: '2012-09-26',
            job: 'Director',
            department: 'Directing',
            status: 5,
          ),
          credit(
            3,
            'Project London',
            date: '2011-06-01',
            job: 'Director',
            department: 'Directing',
          ),
        ],
      }),
      knownFor: 'Directing',
    );

    final lead = shelf.lead!;
    expect(lead.title, 'Directed');
    expect(
      [for (final w in lead.works) w.media.title],
      ['Tears of Steel', 'Project London', 'Next One'],
    );
    expect(lead.onServer(), 1);
    expect(PersonShelf.roleFor('Directing'), 'Director');
  });

  test('someone known for another trade leads with it, by its own name', () {
    final shelf = PersonShelf.of(
      PersonCombinedCredits.fromJson({
        'crew': [
          credit(
            1,
            'Dune',
            date: '2021-09-15',
            job: 'Original Music Composer',
            department: 'Sound',
          ),
        ],
        'cast': [
          credit(2, 'A Cameo', date: '2015-01-01', character: 'Pianist'),
        ],
      }),
      knownFor: 'Sound',
    );

    expect([for (final t in shelf.trades) t.title], ['Sound', 'Acted']);
    expect(PersonShelf.roleFor('Sound'), 'Sound');
  });

  test('TMDB with nothing on screen for them: an empty shelf', () {
    expect(
      PersonShelf.of(PersonCombinedCredits.empty, knownFor: 'Acting').isEmpty,
      isTrue,
    );
  });
}
