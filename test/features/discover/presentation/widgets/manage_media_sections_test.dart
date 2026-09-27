import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/widgets/manage_media_sections.dart';

SeerrRequest _request(RequestStatus status, {RequestMedia? media}) =>
    SeerrRequest(
      id: 1,
      status: status,
      media: media,
      createdAt: '2026-09-01T10:00:00Z',
      type: 'movie',
    );

/// The fill of the status badge that carries [label].
Color _badgeFill(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  final scheme = AppTheme.darkTheme().colorScheme;

  Future<void> pump(WidgetTester tester, SeerrRequest request) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: RequestsSection(requests: [request], onDeleteRequest: (_) {}),
        ),
      ),
    );
  }

  // The badge used to paint declined, failed and deleted all red: the tone that
  // says Seerr did not answer, on a badge that exists because it did.
  group('request status badge', () {
    testWidgets('a declined request is a decision, so neutral', (tester) async {
      await pump(tester, _request(RequestStatus.declined));
      expect(
        _badgeFill(tester, 'Declined'),
        statusToneFill(scheme, StatusTone.neutral),
      );
    });

    testWidgets('a deleted request is backlog, so neutral', (tester) async {
      await pump(
        tester,
        _request(
          RequestStatus.approved,
          media: const RequestMedia(status: SeerrMediaAvailability.deleted),
        ),
      );
      expect(
        _badgeFill(tester, 'Deleted'),
        statusToneFill(scheme, StatusTone.neutral),
      );
    });

    testWidgets('a failed request is a fault, so amber', (tester) async {
      await pump(tester, _request(RequestStatus.failed));
      expect(
        _badgeFill(tester, 'Failed'),
        statusToneFill(scheme, StatusTone.warning),
      );
    });

    testWidgets('no request status is painted red', (tester) async {
      for (final status in RequestStatus.values) {
        final request = _request(status);
        await pump(tester, request);
        final label = request.displayStatus.label;
        expect(
          _badgeFill(tester, label),
          isNot(statusToneFill(scheme, StatusTone.error)),
          reason: label,
        );
      }
    });
  });
}
