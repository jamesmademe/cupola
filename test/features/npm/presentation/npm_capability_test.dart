import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';

import '../../../test_helpers/fixtures.dart';

NpmAccount _fixture(String name) =>
    NpmAccount.fromJson(jsonFixtureMap('npm/$name.json'));

void main() {
  group('the grant an account carries', () {
    test('an admin writes everything', () {
      expect(
        npmGrantFor(_fixture('users_me_admin')),
        const CapabilityGrant.readWrite(),
      );
    });

    test('an account that manages nothing is read-only', () {
      expect(
        npmGrantFor(_fixture('users_me_view_only')),
        const CapabilityGrant.readOnly(),
      );
    });

    test('an account that manages some resources writes exactly those', () {
      // `visibility` scopes rows, never writes, and `hidden` is not `manage`.
      expect(
        npmGrantFor(_fixture('users_me_partial')),
        const CapabilityGrant.partial({'proxy_hosts'}),
      );
    });

    test('no answer is unanswered, never optimistic', () {
      expect(npmGrantFor(null), const CapabilityGrant.unanswered());
    });
  });

  group('the copy', () {
    test('two different sentences for "view-only" and "could not ask"', () {
      final copy = npmCapabilityCopy();
      final answered = copy.bannerFor(const CapabilityGrant.readOnly(), {});
      final unanswered = copy.bannerFor(const CapabilityGrant.unanswered(), {});
      expect(answered, contains('view-only'));
      expect(unanswered, contains('couldn\'t check'));
      expect(answered, isNot(unanswered));
    });

    test('a partial account is told what it cannot change here', () {
      final copy = npmCapabilityCopy();
      expect(
        copy.bannerFor(const CapabilityGrant.partial({'proxy_hosts'}), {
          'certificates',
        }),
        'This Nginx Proxy Manager account can read certificates but not '
        'change them. Changing them needs an account that can manage '
        'certificates.',
      );
    });

    test('a refusal names the resource it was refused on', () {
      expect(
        npmCapabilityCopy(NpmResource.certificates).refusal,
        'Nginx Proxy Manager refused this change. This account can read but '
        'not change certificates.',
      );
    });

    test('the hint is the one NPM always carried', () {
      expect(npmCapabilityCopy().hint, 'requires an admin account');
    });
  });
}
