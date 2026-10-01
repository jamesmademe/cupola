import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared state and helpers for loading quality profiles in detail screens.
///
/// ## A read that came back with nothing is not the last word
///
/// The profiles used to be asked for once per page. A read that failed, or
/// that the service swallowed into an empty list (the \*arr services' profile
/// read does), left [qualityProfiles] empty for as long as the page was open:
/// the row is drawn only over a list it can offer, so it was gone for good,
/// even after a Retry brought the page itself back.
///
/// So an empty answer is asked for again, once, each time the page's own
/// record arrives fresh: the `record` a screen passes to
/// [ensureQualityProfiles] is the object its provider answered with, and a
/// Retry, a pull or a recovery mints a new one. Until then the row stays
/// omitted, which says nothing rather than something wrong. Keyed on the
/// record rather than on every build, because a page rebuilds for many
/// reasons and a read failing on each of them would be a loop.
mixin QualityProfileMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  List<Map<String, dynamic>> qualityProfiles = [];
  String? currentProfileName;
  int? currentProfileId;
  bool _profilesRequested = false;
  bool _profilesInFlight = false;
  Object? _profilesAskedFor;
  int? _boundProfileId;

  /// Asks for the profiles the first time, and again when an empty answer is
  /// followed by a fresh [record]. See the mixin's doc.
  ///
  /// [record] is optional: a screen that passes none keeps the old
  /// ask-once behaviour.
  void ensureQualityProfiles({
    required int? profileId,
    required Future<List<Map<String, dynamic>>> Function() fetchProfiles,
    Object? record,
  }) {
    final askAgain =
        _profilesRequested &&
        !_profilesInFlight &&
        qualityProfiles.isEmpty &&
        record != null &&
        !identical(record, _profilesAskedFor);
    if (!_profilesRequested || askAgain) {
      _profilesRequested = true;
      _profilesInFlight = true;
      _profilesAskedFor = record;
      _boundProfileId = profileId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        loadQualityProfiles(
          fetchProfiles: fetchProfiles,
          initialProfileId: profileId,
        );
      });
      return;
    }

    if (qualityProfiles.isNotEmpty && _boundProfileId != profileId) {
      _boundProfileId = profileId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        setState(() {
          currentProfileId = profileId;
          currentProfileName = getProfileName(profileId);
        });
      });
    }
  }

  Future<void> loadQualityProfiles({
    required Future<List<Map<String, dynamic>>> Function() fetchProfiles,
    required int? initialProfileId,
  }) async {
    try {
      final profiles = await fetchProfiles();
      if (!mounted) return;

      setState(() {
        _profilesInFlight = false;
        qualityProfiles = profiles;
        currentProfileId = initialProfileId;
        currentProfileName = getProfileName(initialProfileId);
      });
    } catch (_) {
      if (!mounted) return;
      // Rebuilt rather than ignored: a record that arrived while this read was
      // in flight is then asked for, instead of waiting for a rebuild that may
      // not come. The row stays omitted meanwhile.
      setState(() => _profilesInFlight = false);
    }
  }

  String? getProfileName(int? profileId) {
    if (profileId == null) return null;

    final profile = qualityProfiles
        .where((p) => p['id'] == profileId)
        .firstOrNull;
    return profile?['name'] as String?;
  }

  void updateProfileState(int profileId) {
    setState(() {
      currentProfileId = profileId;
      currentProfileName = getProfileName(profileId);
    });
  }
}
