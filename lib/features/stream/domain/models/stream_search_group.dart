/// One band of a media-server search result, kept in the order the server gave
/// it.
///
/// **Grouping is the answer, not a presentation choice.** Both servers return a
/// library search already sorted into kinds — Jellyfin because `/Search/Hints`
/// types every hint, Plex because `/hubs/search` answers in hubs — and a client
/// that flattens them throws away the one thing that makes five hits readable.
/// Worse, it makes the two servers disagree: a flattened Plex search puts
/// whatever the server ranked first at the top, and the page has no way to say
/// what band it belongs to.
///
/// **An empty group is a result.** A band with no items stays in the list and
/// draws as a zero pill, because the strip has to say what was *searched* rather
/// than only what answered — "Episodes 0" is the difference between "this server
/// holds no matching episode" and "we never asked". Callers must therefore not
/// filter on [isEmpty]; it exists to let the pill style itself.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/features/stream/domain/models/stream_item.dart';

@immutable
class StreamSearchGroup {
  /// The band's name, in the server's own words where it has them.
  ///
  /// Plex supplies the hub title verbatim; Jellyfin has no equivalent, so the
  /// client names the band after the hint type it asked for. Either way the page
  /// prints this rather than deriving a word from [kind], so a server that
  /// renames a hub is followed instead of contradicted.
  final String label;

  /// The kind this band holds, when the band is about exactly one.
  ///
  /// Null for a Plex hub that mixes kinds or names something [StreamItemKind]
  /// has no word for (a Plex `actor` hub, a Jellyfin `Person` hint): the page
  /// still draws the band from [label], and nothing downstream has to invent a
  /// vocabulary entry for a row it cannot open.
  final StreamItemKind? kind;

  final List<StreamItem> items;

  const StreamSearchGroup({
    required this.label,
    required this.kind,
    required this.items,
  });

  bool get isEmpty => items.isEmpty;

  int get count => items.length;
}
