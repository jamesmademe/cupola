/// Which numbering a Seerr server's media codes follow.
///
/// The codes are the same up to 5 (UNKNOWN 1, PENDING 2, PROCESSING 3,
/// PARTIALLY AVAILABLE 4, AVAILABLE 5) and part ways after it: Overseerr calls
/// 6 DELETED, while Seerr, and Jellyseerr before it, call 6 BLOCKLISTED and 7
/// DELETED (`server/constants/media.ts` in `sct/overseerr` and in
/// `seerr-team/seerr`). The same 6 is a title anyone may request again on one
/// server and a title the operator has barred on the other, so a code is
/// decoded only together with the numbering of the server that sent it
/// (`SeerrMediaAvailability.fromCode`).
enum SeerrNumbering {
  /// Seerr and Jellyseerr: BLOCKLISTED 6, DELETED 7.
  seerr,

  /// Overseerr: DELETED 6, and no 7.
  overseerr;

  /// The numbering of a server that reports [version] from `/api/v1/status`.
  ///
  /// Overseerr has only ever shipped 1.x. Every other version, a Seerr or
  /// Jellyseerr release and the `develop-<sha>` builds both of them report,
  /// is read as Seerr's. Null when the server said no version, which leaves
  /// a 6 undecided rather than guessed.
  static SeerrNumbering? fromVersion(String? version) {
    final text = version?.trim() ?? '';
    if (text.isEmpty) return null;
    final bare = text.startsWith('v') || text.startsWith('V')
        ? text.substring(1)
        : text;
    final major = int.tryParse(bare.split('.').first);
    return major == 1 ? SeerrNumbering.overseerr : SeerrNumbering.seerr;
  }
}
