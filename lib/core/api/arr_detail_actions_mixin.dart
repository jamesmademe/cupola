import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:go_router/go_router.dart';

import 'package:cupola/core/api/quality_profile_mixin.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';

/// The write actions every *arr library detail screen offers on the title it is
/// showing: monitor on/off, change quality profile, auto-search, delete.
///
/// Radarr's, Sonarr's and Lidarr's detail screens ran three byte-for-byte
/// copies of these handlers, differing only in the service name, the subject
/// noun and which service method to call — so the confirmation wording, the
/// haptics, the `mounted` guards and the busy-flag bookkeeping drifted three
/// ways every time one of them was touched. They are stated once here.
///
/// Sits beside [QualityProfileMixin] and depends on it: [changeProfile] reads
/// the currently bound profile from it and writes the new one back through
/// [QualityProfileMixin.updateProfileState].
mixin ArrDetailActionsMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, QualityProfileMixin<T> {
  /// True while the promoted auto-search is in flight.
  bool isAutoSearching = false;

  /// True for [AppAnimation.confirmationHold] after a search was accepted, so
  /// the promoted action can show that the server took it.
  bool isAutoSearchConfirmed = false;

  /// True while the delete write is in flight.
  bool isDeleting = false;

  /// True while the monitored-flag write is in flight.
  bool isUpdatingMonitoredState = false;

  Timer? _searchConfirmTimer;

  @override
  void dispose() {
    _searchConfirmTimer?.cancel();
    super.dispose();
  }

  /// Holds the "search accepted" state for [AppAnimation.confirmationHold],
  /// then releases it.
  void showSearchConfirmation() {
    if (!mounted) return;
    setState(() => isAutoSearchConfirmed = true);
    _searchConfirmTimer?.cancel();
    _searchConfirmTimer = Timer(AppAnimation.confirmationHold, () {
      if (mounted) setState(() => isAutoSearchConfirmed = false);
    });
  }

  /// Flips the monitored flag, invalidating [invalidate] on success.
  ///
  /// [subject] is the noun the service tracks — `movie`, `series`, `artist`.
  Future<void> setMonitored({
    required BuildContext context,
    required String serviceName,
    required String subject,
    required bool monitored,
    required Future<void> Function() write,
    required List<ProviderOrFamily> invalidate,
  }) async {
    setState(() => isUpdatingMonitoredState = true);
    try {
      await write();
      if (!context.mounted) return;
      for (final provider in invalidate) {
        ref.invalidate(provider);
      }
      // What changed, in the words of the thing that will act on it. "Movie
      // unmonitored" states a flag; "Radarr has stopped monitoring" states the
      // consequence, and Monitored is a term a self-hoster genuinely needs.
      SnackBarHelper.success(
        context,
        monitored
            ? '$serviceName is monitoring this $subject'
            : '$serviceName has stopped monitoring this $subject',
      );
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change monitoring in $serviceName.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => isUpdatingMonitoredState = false);
    }
  }

  /// Changes the quality profile behind a confirmation that names the
  /// transition and its consequence.
  ///
  /// This used to fire straight off a tap in the icon row, which made a
  /// server-side write with real cost — an *arr can start hunting upgrades for
  /// the whole title the moment the profile lands — the one action on the page
  /// with no confirmation and no way back. An Undo would be a lie here: putting
  /// the old profile back does not recall searches that are already queued on
  /// the user's connection, so the recoverable moment is *before* the write.
  ///
  /// [consequence] is the only part of that sentence the three services do not
  /// share: what exactly gets re-searched (`an upgrade` for a single movie,
  /// `upgrades across every monitored episode`, `…album`).
  Future<void> changeProfile({
    required int profileId,
    required String mediaTitle,
    required String serviceName,
    required String consequence,
    required Future<void> Function() write,
    required List<ProviderOrFamily> invalidate,
  }) async {
    if (profileId == currentProfileId) return;

    final from = currentProfileName ?? 'its current profile';
    final to = getProfileName(profileId) ?? 'the selected profile';

    final result = await showAppConfirmDialog(
      context: context,
      title: 'Change quality profile?',
      icon: Icons.high_quality_rounded,
      message:
          '${truncateTitle(mediaTitle)} moves from $from to $to. '
          '$serviceName may start searching for $consequence as soon as this '
          'lands, and a search cannot be called back from here.',
      confirmLabel: 'Change profile',
    );

    if (!result.confirmed || !mounted) return;

    try {
      await write();
      if (mounted) {
        updateProfileState(profileId);
        for (final provider in invalidate) {
          ref.invalidate(provider);
        }
        SnackBarHelper.success(context, 'Quality profile changed to $to');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change the quality profile in $serviceName.",
        detail: e,
      );
    }
  }

  /// Confirms and performs a delete, popping the detail route on success.
  ///
  /// [write] receives the two choices the dialog offers, in that order.
  Future<void> confirmDelete({
    required BuildContext context,
    required String serviceName,
    required String subject,
    required String title,
    required DeleteMediaType mediaType,
    required Future<void> Function(bool deleteFiles, bool addExclusion) write,
  }) async {
    // The destructive button announces itself in the hand before the dialog
    // arrives. Tactility is a property of the action, not of which service
    // happens to own the screen.
    HapticFeedback.mediumImpact();

    final result = await showDeleteMediaDialog(
      context: context,
      // The dialog builds "Delete <title>?" as its heading, which sits above
      // the scrollable content in an AlertDialog — so a 200-character release
      // name pushes the two checkboxes and both buttons off the screen. Capped
      // here, where the untrusted string enters.
      title: truncateTitle(title),
      mediaType: mediaType,
    );

    if (!result.confirmed || !context.mounted) return;

    setState(() => isDeleting = true);
    try {
      await write(result.deleteFiles, result.addExclusion);
      if (!context.mounted) return;
      // "Movie deleted" left the one thing the user just decided unstated. The
      // dialog offered two different destructions; the confirmation says which
      // one happened.
      SnackBarHelper.success(
        context,
        result.deleteFiles
            ? 'Removed from $serviceName and deleted from disk'
            : 'Removed from $serviceName',
      );
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't delete this $subject from $serviceName.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => isDeleting = false);
    }
  }

  /// Launches the title-wide automatic search.
  ///
  /// [successMessage] is the whole sentence: the three services search
  /// different scopes ("this movie", "every monitored episode", "every
  /// monitored album"), so only the shape — `"<Service> is searching <what>"` —
  /// is shared, not the words.
  Future<void> triggerSearch({
    required BuildContext context,
    required String serviceName,
    required String successMessage,
    required Future<void> Function() search,
  }) async {
    HapticFeedback.selectionClick();
    setState(() => isAutoSearching = true);
    try {
      await search();
      if (!context.mounted) return;
      SnackBarHelper.success(context, successMessage);
      showSearchConfirmation();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search in $serviceName.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => isAutoSearching = false);
    }
  }
}
