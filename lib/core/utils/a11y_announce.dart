import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Speaks [message] through the platform's screen reader.
///
/// Use this **only** where a state change leaves nothing new on screen: a
/// refresh that reloads the same list in place, a filter that reorders it, a
/// toggle whose only feedback was a colour. An announcement interrupts
/// VoiceOver's speech queue, so a spinner, a route change or a `SnackBar` is
/// always the better answer.
///
/// One entry point, two channels, and never both for the same message:
///
///  * Where the engine reports announcement support (iOS, macOS, Windows) the
///    message goes out natively, through [SemanticsService.sendAnnouncement].
///  * Where it does not — Android, whose engine sets `NO_ANNOUNCE`
///    unconditionally because an announcement event makes TalkBack clear its
///    speech queue — the message is handed to the app's [AnnouncementHost],
///    which draws it as a polite live region. That is the channel Android
///    offers in place of announcements, and the one the framework itself falls
///    back to (`InputDecorator` marks its error `liveRegion` exactly when
///    `supportsAnnounceOf` is false). [assertiveness] has no effect there: the
///    engine only ever reports a live region as polite.
///
/// Decided per call from [MediaQuery.supportsAnnounceOf], never from the
/// platform, so call sites never branch and a platform whose engine gains the
/// channel moves over without a change here.
///
/// A `SnackBar` already carries `liveRegion: true`, and so do dialogs and error
/// states. Announcing alongside one means the user hears it twice — on every
/// platform, now that Android has a channel too — which is why `SnackBarHelper`
/// deliberately does *not* route through here.
///
/// Linux is the gap: its engine reports announcement support but ignores the
/// message, and exposes no live regions either. So an announcement is still
/// never a message's only channel.
///
/// Wraps [SemanticsService.sendAnnouncement] rather than
/// `SemanticsService.announce`: the latter is deprecated after Flutter 3.35 and
/// CI runs `flutter analyze --fatal-infos`.
void announce(
  BuildContext context,
  String message, {
  Assertiveness assertiveness = Assertiveness.polite,
}) {
  if (message.isEmpty) return;

  if (MediaQuery.supportsAnnounceOf(context)) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
      assertiveness: assertiveness,
    );
    return;
  }

  // Without a host above [context] the live region has nowhere to be drawn and
  // the message is lost; `CupolaApp` mounts one in `MaterialApp.builder`.
  context.getInheritedWidgetOfExactType<_AnnouncementScope>()?.host._speak(
    message,
  );
}

/// The app's one polite live region: where [announce] speaks when the engine
/// has no announcement channel.
///
/// Mounted once, around the whole app in `MaterialApp.builder`, so it sits
/// above every route — the shell, the routes outside it, dialogs — and paints
/// after the navigator, where no route's `BlockSemantics` can reach it. On a
/// platform with the native channel it draws nothing and costs one `Stack`.
///
/// Each message is drawn as a node of its own, 1 × 1 at the top-left corner
/// (an empty rect is dropped from the semantics tree), carrying the message as
/// its label. Android's bridge speaks a live region when its label changes, and
/// a node that has just appeared counts as changed; so a node of its own is
/// what lets the same sentence, sent twice, be heard twice — a label set to the
/// value it already holds changes nothing and says nothing.
///
/// **Messages close together are coalesced within a frame and kept apart
/// across frames.** Everything announced before the next frame draws becomes
/// one node whose label joins the messages, in order, a line each: one
/// content-change event rather than a burst of them, which TalkBack's event
/// queue is free to thin out. A message after that frame gets a node of its
/// own, and the nodes before it are left alone: each stays in the tree for
/// [linger] from its first message, so none is taken away before the reader
/// has fetched it, and keys keep an earlier node's expiry from relabelling a
/// later one — which would announce the later sentence a second time.
///
/// The cost is that for [linger] a reader walking the screen can land on the
/// sentence it just heard. It is gone after that.
class AnnouncementHost extends StatefulWidget {
  const AnnouncementHost({super.key, required this.child});

  /// The app. Never rebuilt or re-parented by an announcement.
  final Widget child;

  /// How long a message's node stays in the tree.
  ///
  /// Long enough that TalkBack, which fetches the node when it handles the
  /// event, never finds it already gone; short enough that the sentence does
  /// not stay behind as something to swipe past.
  static const Duration linger = Duration(seconds: 5);

  @override
  State<AnnouncementHost> createState() => _AnnouncementHostState();
}

class _AnnouncementScope extends InheritedWidget {
  const _AnnouncementScope({required this.host, required super.child});

  final _AnnouncementHostState host;

  // Nothing depends on it: [announce] looks it up without subscribing.
  @override
  bool updateShouldNotify(_AnnouncementScope oldWidget) => false;
}

/// One node's worth of speech: every message announced before a frame drew it.
class _Batch {
  _Batch(this.text);

  String text;

  /// Set once a build has put [text] on screen; from then on its label is
  /// final, and a new message starts a batch of its own.
  bool drawn = false;

  Timer? expiry;
}

class _AnnouncementHostState extends State<AnnouncementHost> {
  final List<_Batch> _batches = <_Batch>[];

  void _speak(String message) {
    final pending = _batches.lastOrNull;
    if (pending != null && !pending.drawn) {
      pending.text = '${pending.text}\n$message';
    } else {
      final batch = _Batch(message);
      batch.expiry = Timer(AnnouncementHost.linger, () => _expire(batch));
      _batches.add(batch);
    }
    _markNeedsBuild();
  }

  void _markNeedsBuild() {
    if (!mounted) return;
    // An announcement made from a build or layout callback cannot dirty an
    // ancestor mid-frame; it is drawn by the frame after instead.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => _markNeedsBuild())
        ..ensureVisualUpdate();
      return;
    }
    setState(() {});
  }

  void _expire(_Batch batch) {
    if (!mounted) return;
    setState(() => _batches.remove(batch));
  }

  @override
  void dispose() {
    for (final batch in _batches) {
      batch.expiry?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final batch in _batches) {
      batch.drawn = true;
    }

    return _AnnouncementScope(
      host: this,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          for (final batch in _batches)
            Positioned(
              key: ObjectKey(batch),
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: Semantics(
                container: true,
                liveRegion: true,
                label: batch.text,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}
