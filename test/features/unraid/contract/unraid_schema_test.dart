import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/unraid/data/unraid_client.dart';

/// Tier-3 contract test (plan §7.4). Unraid has no formal OpenAPI spec, so the
/// committed GraphQL SDL is the contract: a lightweight substring check (no gql
/// dependency) fails loudly if a type/field the [UnraidClient] queries is
/// renamed upstream. Refresh `unraid/schema.graphql` from introspection against
/// a pinned instance to update the contract (plan §9 contract-drift job).
///
/// Read the header of the fixture before trusting this too far: it is written
/// from the published schema reference rather than captured, so what the two
/// tests below prove is that the client and the fixture agree. That is worth
/// having — a GraphQL server rejects the whole document over one unknown
/// field, so a selection nobody wrote down takes an entire tab down — but it
/// is not evidence about the real server.
void main() {
  group('Unraid GraphQL SDL contract', () {
    final sdl = File('test/fixtures/unraid/schema.graphql').readAsStringSync();

    test('the queried types and fields still exist in the schema', () {
      for (final needle in const [
        // top-level queries
        'info:',
        'array:',
        'dockerContainers:',
        'me:',
        'notifications:',
        'shares:',
        'vms:',
        // info → os → distro/release/uptime
        'type Os',
        'distro:',
        'release:',
        'uptime:',
        // array → state / capacity.kilobytes / disks
        'type Array',
        'type ArrayCapacity',
        'kilobytes:',
        'type ArrayDisk',
        'temp:',
        // dockerContainers fields
        'type DockerContainer',
        'names:',
        'autoStart:',
        'type VmDomain',
        'type VmMutations',
        'archiveNotification',
        'type Notification',
        'input NotificationFilter',
        'type Share',
      ]) {
        expect(
          sdl,
          contains(needle),
          reason: 'Unraid schema changed: "$needle" is gone',
        );
      }
    });

    // The list above only proves the names somebody remembered to write down
    // are still there. This one walks the documents the client actually sends,
    // which is the check that catches the opposite mistake: a field the client
    // selects that nobody ever declared. Five of those (`allocator`,
    // `splitLevel`, `floor`, `cow`, `color`) once shipped in the `shares`
    // selection past a green suite, and a GraphQL server answers an unknown
    // field by rejecting the whole document — so the Shares tab would have
    // been dead on the first real instance, not merely missing five values.
    test('every field the client selects is declared in the schema', () {
      final declared = _identifiers(sdl);

      UnraidClient.graphQlDocuments.forEach((call, document) {
        for (final name in _selectedNames(document)) {
          expect(
            declared,
            contains(name),
            reason:
                '$call selects "$name", which the committed SDL does not '
                'declare. One unknown field fails the entire document.',
          );
        }
      });
    });
  });
}

/// Every bare identifier in [source], for membership tests.
Set<String> _identifiers(String source) => RegExp(
  r'[A-Za-z_][A-Za-z0-9_]*',
).allMatches(source).map((match) => match[0]!).toSet();

/// The field names, argument names and input type names one GraphQL document
/// asks the server for.
///
/// The operation header is dropped except for its variable *types*: an
/// operation name (`VmAction`) is ours to choose and means nothing to the
/// schema, while `NotificationFilter!` is a contract. Variable references
/// (`$id`) are dropped for the same reason — the name belongs to the document.
Set<String> _selectedNames(String document) {
  final header = RegExp(
    r'^\s*(query|mutation)\s+(\w*)\s*(\(([^)]*)\))?\s*',
  ).firstMatch(document);
  final names = <String>{};

  if (header != null) {
    // `($filter: NotificationFilter!, $id: PrefixedID!)` → the type halves.
    for (final declaration in (header[4] ?? '').split(',')) {
      final parts = declaration.split(':');
      if (parts.length < 2) continue;
      final type = parts[1].replaceAll(RegExp(r'[\[\]!\s]'), '');
      if (type.isNotEmpty) names.add(type);
    }
  }

  final body = document.substring(header?.end ?? 0);
  // Drop `$variable` references before tokenising, so the leading `$` cannot
  // be lost and leave a bare name behind.
  final selections = body.replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), ' ');
  names.addAll(_identifiers(selections));
  return names;
}
