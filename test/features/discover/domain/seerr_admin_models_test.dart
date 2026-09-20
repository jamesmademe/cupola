import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';

void main() {
  test(
    'parses the documented issue shape and keeps optional fields optional',
    () {
      final issue = SeerrIssue.fromJson({
        'id': '21',
        'issueType': '2',
        'media': {'title': 'Fight Club'},
        'createdBy': {'username': 'matt'},
        'comments': [
          {'id': 1},
        ],
      });

      expect(issue.id, 21);
      expect(issue.issueTypeLabel, 'Audio');
      expect(issue.media?.title, 'Fight Club');
      expect(issue.createdBy?.displayName, 'matt');
      expect(issue.commentCount, 1);
      expect(issue.tone.name, 'warning');
    },
  );

  test('uses safe fallbacks for a sparse user', () {
    final user = SeerrUser.fromJson({'id': 4, 'email': 'matt@example.com'});

    expect(user.displayName, 'matt@example.com');
    expect(user.requestCount, isNull);
  });
}
