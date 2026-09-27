import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';

void main() {
  group('scopeFor', () {
    test('a whole-connection grant answers the same for every resource', () {
      for (final (grant, scope) in [
        (const CapabilityGrant.readWrite(), CapabilityScope.readWrite),
        (const CapabilityGrant.readOnly(), CapabilityScope.readOnly),
        (const CapabilityGrant.unanswered(), CapabilityScope.readOnly),
        (const CapabilityGrant.refused(), CapabilityScope.readOnly),
        (const CapabilityGrant.unknown(), CapabilityScope.unknown),
      ]) {
        expect(grant.scopeFor(null), scope, reason: '$grant');
        expect(grant.scopeFor('vms'), scope, reason: '$grant');
      }
    });

    test('a partial grant writes what it names and only that', () {
      const grant = CapabilityGrant.partial({'proxy_hosts'});
      expect(grant.scopeFor('proxy_hosts'), CapabilityScope.readWrite);
      // A resource the probe did not mention is one it did not say could be
      // written: the fallback rule, per resource.
      expect(grant.scopeFor('certificates'), CapabilityScope.readOnly);
      // Something on the connection can change, so the connection is writable.
      expect(grant.scopeFor(null), CapabilityScope.readWrite);
    });

    test('the three restricted bases are one scope and three facts', () {
      const restricted = [
        CapabilityGrant.readOnly(),
        CapabilityGrant.unanswered(),
        CapabilityGrant.refused(),
      ];
      expect(restricted.map((g) => g.scope).toSet(), {
        CapabilityScope.readOnly,
      });
      expect(restricted.map((g) => g.basis).toList(), [
        CapabilityBasis.answered,
        CapabilityBasis.unanswered,
        CapabilityBasis.refused,
      ]);
    });
  });

  group('restrictsAny', () {
    test('null asks about the connection as a whole', () {
      expect(const CapabilityGrant.readOnly().restrictsAny(null), isTrue);
      expect(const CapabilityGrant.unanswered().restrictsAny(null), isTrue);
      expect(const CapabilityGrant.refused().restrictsAny(null), isTrue);
      expect(const CapabilityGrant.readWrite().restrictsAny(null), isFalse);
      expect(const CapabilityGrant.unknown().restrictsAny(null), isFalse);
      // A partial account is not wholly restricted.
      expect(const CapabilityGrant.partial({'a'}).restrictsAny(null), isFalse);
    });

    test('a set asks whether any of the page\'s resources is restricted', () {
      const grant = CapabilityGrant.partial({'vms'});
      expect(grant.restrictsAny({'vms'}), isFalse);
      expect(grant.restrictsAny({'notifications'}), isTrue);
      expect(grant.restrictsAny({'vms', 'notifications'}), isTrue);
      expect(grant.restrictsAny(const <String>{}), isFalse);
      expect(const CapabilityGrant.unknown().restrictsAny({'vms'}), isFalse);
      expect(const CapabilityGrant.readOnly().restrictsAny({'vms'}), isTrue);
    });
  });

  group('equality', () {
    test('is structural, and a writable set compares as a set', () {
      expect(
        const CapabilityGrant.partial({'a', 'b'}),
        const CapabilityGrant.partial({'b', 'a'}),
      );
      expect(
        const CapabilityGrant.partial({'a', 'b'}).hashCode,
        const CapabilityGrant.partial({'b', 'a'}).hashCode,
      );
      expect(
        const CapabilityGrant.partial({'a'}),
        isNot(const CapabilityGrant.partial({'b'})),
      );
      expect(
        const CapabilityGrant.readOnly(),
        isNot(const CapabilityGrant.unanswered()),
      );
      expect(
        const CapabilityGrant.readWrite(),
        isNot(const CapabilityGrant.partial({'a'})),
      );
      expect(const CapabilityGrant.refused(), const CapabilityGrant.refused());
    });
  });
}
