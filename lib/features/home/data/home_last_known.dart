/// The Home's last known state: what each module drew the last time it had a
/// live answer, drawn again at a cold start until the live answer comes.
///
/// The store and why it keeps drawings rather than responses are in
/// `LastKnownStore`. This is the Home's side: which modules keep one
/// ([HomeLastKnownSlot]), for which connections, and how a module reads "the
/// live answer, or else the last known one" in one call
/// ([HomeLastKnownWatch.watchOrLastKnown]).
///
/// What stays out, on purpose: Needs you and the header's health (a fault of
/// yesterday is a false alarm today, P-t1-no-faults) and Now playing (live by
/// nature). Activity and Discover keep nothing: they read the providers the
/// Home already made live by the time they are a tap away.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// One module's last drawing: its name in the store, the shape of its data,
/// the services it reads (whose connections the drawing is valid for), and
/// its codec.
///
/// [encode] turns the module's live value into JSON with no credential in it
/// (pictures through `StoredImage`, times as instants), or answers null for a
/// value not worth keeping (every source silent: the drawing before it is the
/// better one). [decode] turns it back, with pictures resolved against the
/// connections as they are now; null for anything it cannot read, which the
/// module takes as nothing known. Bump [schema] whenever the JSON changes
/// shape: an entry of another schema is dropped rather than misread.
@immutable
class HomeLastKnownSlot<T> {
  const HomeLastKnownSlot({
    required this.id,
    required this.schema,
    required this.services,
    required this.encode,
    required this.decode,
  });

  final String id;
  final int schema;
  final Set<ServiceKey> services;
  final Object? Function(T value) encode;
  final T? Function(Object? data, StoredImageResolver image) decode;
}

/// A module's value with where it came from: live ([asOf] null), or the last
/// drawing, as of [asOf]; and the live read itself, for whether it is still
/// being asked for or failed.
typedef HomeRead<T> = ({T? value, DateTime? asOf, AsyncValue<T> live});

/// What the drawings of [services] are valid for: each of their connections
/// as it is set up (service, id, address, user, viewer, the Seerr account),
/// never a secret. A change to any of them is a different server or a
/// different person, and the drawing is dropped.
String homeLastKnownValidity(SettingsModel settings, Set<ServiceKey> services) {
  final parts = [
    for (final instance in settings.instances)
      if (services.contains(instance.service) && instance.url.isNotEmpty)
        [
          instance.service.name,
          instance.id,
          instance.url,
          instance.username,
          instance.viewerId,
          instance.account?.userId ?? '',
        ].join('|'),
  ]..sort();
  return parts.join(';');
}

/// The store key of [slot] for [audience]: the two Homes keep theirs apart.
String homeLastKnownKey(String audience, HomeLastKnownSlot<Object?> slot) =>
    'home.$audience.${slot.id}';

/// [slot]'s last drawing for the Home on screen, decoded, or null.
///
/// Read once per slot and connections, not on every build: it is what the
/// module draws until its live answer comes, after which nothing reads it.
final homeLastKnownProvider = Provider.autoDispose
    .family<({Object? value, DateTime asOf})?, HomeLastKnownSlot<Object?>>((
      ref,
      slot,
    ) {
      final audience = ref.watch(shellAudienceProvider).name;
      final settings = ref.watch(currentSettingsProvider);
      final entry = ref
          .read(lastKnownStoreProvider)
          .read(
            homeLastKnownKey(audience, slot),
            validity: homeLastKnownValidity(settings, slot.services),
            schema: slot.schema,
          );
      if (entry == null) return null;
      try {
        final value = slot.decode(
          entry.data,
          (image) => resolveStoredImage(ref, settings, image),
        );
        if (value == null) return null;
        return (value: value, asOf: entry.takenAt);
      } catch (_) {
        return null;
      }
    });

/// A kept picture with the headers its connection sends today; nothing, for
/// a connection that is gone, and no credential to an address that is not the
/// connection's own.
ImageSource resolveStoredImage(
  Ref ref,
  SettingsModel settings,
  StoredImage image,
) {
  switch (image) {
    case StoredUrl(:final url):
      return (url: url, headers: null);
    case StoredArrImage(:final connectionId, :final url):
      final instance = settings.instanceById(connectionId);
      if (instance == null || instance.credential.isEmpty) return noImage;
      if (!_sameOrigin(url, instance.url)) return (url: url, headers: null);
      return (
        url: url,
        headers: {
          ...ConnectionAccessRegistry.headersFor(instance.url),
          'X-Api-Key': instance.credential,
        },
      );
    case StoredStreamImage(:final service, :final connectionId, :final path):
      if (settings.instanceById(connectionId) == null) return noImage;
      final source = switch (service) {
        ServiceKey.jellyfin =>
          ref
              .read(jellyfinClientForProvider(connectionId))
              .imageFor(path, width: image.width),
        ServiceKey.plex =>
          ref
              .read(plexClientForProvider(connectionId))
              .imageFor(path, width: image.width),
        _ => null,
      };
      return source ?? noImage;
  }
}

bool _sameOrigin(String url, String base) {
  final a = Uri.tryParse(url);
  final b = Uri.tryParse(base);
  if (a == null || b == null) return false;
  return a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}

extension HomeLastKnownWatch on WidgetRef {
  /// [live]'s value when it has one, kept as [slot]'s last drawing; until it
  /// has one, the last drawing, with the time it is as of.
  ///
  /// Kept from the module's build because a module is built only while it is
  /// on (or near) the screen: what is kept is what the person saw, and a
  /// module scrolled far away neither loads nor writes. The write is cheap
  /// (an identical value is not encoded again) and lands on disk once the
  /// burst of answers has passed.
  HomeRead<T> watchOrLastKnown<T>(
    ProviderListenable<AsyncValue<T>> live,
    HomeLastKnownSlot<T> slot,
  ) {
    final read = watch(live);
    if (read.value case final T value?) {
      _keep(this, slot, value);
      return (value: value, asOf: null, live: read);
    }
    final known = watch(homeLastKnownProvider(slot));
    if (known == null) return (value: null, asOf: null, live: read);
    return (value: known.value as T, asOf: known.asOf, live: read);
  }
}

void _keep<T>(WidgetRef ref, HomeLastKnownSlot<T> slot, T value) {
  final store = ref.read(lastKnownStoreProvider);
  final key = homeLastKnownKey(ref.read(shellAudienceProvider).name, slot);
  final validity = homeLastKnownValidity(
    ref.read(currentSettingsProvider),
    slot.services,
  );
  // The same answer, rebuilt: already kept.
  if (value is Object && store.holds(key, validity: validity, source: value)) {
    return;
  }
  final data = slot.encode(value);
  if (data == null) return;
  store.write(
    key,
    validity: validity,
    schema: slot.schema,
    data: data,
    takenAt: ref.read(calendarClockProvider)(),
    source: value,
  );
}

/// The modules drawing their last known state right now, and as of when;
/// what the Home's one line reads (`HomeAsOfLine`).
///
/// Not provider state: a module says it from its widget's own life
/// ([LastKnownMark]), and a module scrolled out of the tree takes its mark
/// with it. Listeners hear after the frame, never during a build.
class HomeLastKnownMarks extends ChangeNotifier {
  final Map<Object, ({DateTime asOf, bool checking})> _marks = {};
  bool _scheduled = false;
  bool _disposed = false;

  @override
  void dispose() {
    // A mark leaving the tree with the scope that held this hears nothing.
    _disposed = true;
    super.dispose();
  }

  /// The marks now: what the line reads.
  Iterable<({DateTime asOf, bool checking})> get marks => _marks.values;

  void _set(Object key, ({DateTime asOf, bool checking})? mark) {
    if (_disposed) return;
    final before = _marks[key];
    if (mark == null) {
      if (_marks.remove(key) == null) return;
    } else {
      if (before == mark) return;
      _marks[key] = mark;
    }
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

final homeLastKnownMarksProvider = Provider<HomeLastKnownMarks>((ref) {
  final marks = HomeLastKnownMarks();
  ref.onDispose(marks.dispose);
  return marks;
});

/// Says, for as long as it is in the tree, that [child] is a last drawing as
/// of [asOf] (nothing when [asOf] is null), and whether the live answer is
/// still being asked for ([checking]).
class LastKnownMark extends ConsumerStatefulWidget {
  const LastKnownMark({
    super.key,
    required this.asOf,
    required this.checking,
    required this.child,
  });

  final DateTime? asOf;
  final bool checking;
  final Widget child;

  @override
  ConsumerState<LastKnownMark> createState() => _LastKnownMarkState();
}

class _LastKnownMarkState extends ConsumerState<LastKnownMark> {
  late final HomeLastKnownMarks _marks = ref.read(homeLastKnownMarksProvider);

  @override
  void initState() {
    super.initState();
    _say();
  }

  @override
  void didUpdateWidget(LastKnownMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _say();
  }

  void _say() => _marks._set(this, switch (widget.asOf) {
    final asOf? => (asOf: asOf, checking: widget.checking),
    null => null,
  });

  @override
  void dispose() {
    _marks._set(this, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The Home's one line about its last known state: `As of 20:53 · checking
/// now` while a module draws one and its answer is being asked for, `As of
/// 20:53` once only failures are left; the oldest of them, since the line
/// speaks for all.
///
/// The day as the rows of people say it (`As of yesterday 20:53`, `As of
/// Wednesday 20:53`, then `As of Tue 29 Sep`): the brand book's `As of
/// 20:53`, a snapshot's own words.
String? homeAsOfWords(
  Iterable<({DateTime asOf, bool checking})> marks, {
  required DateTime now,
}) {
  if (marks.isEmpty) return null;
  final oldest = marks
      .map((mark) => mark.asOf)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final checking = marks.any((mark) => mark.checking);
  return [
    'As of ${formatAsOf(oldest, now: now)}',
    if (checking) 'checking now',
  ].join(' · ');
}

/// When a snapshot was taken, as `As of …` finishes it: `20:53` today,
/// `yesterday 20:53`, `Wednesday 20:53` within the week, then the date alone
/// (`Tue 29 Sep`).
String formatAsOf(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  final day = formatPastDay(local, now: now);
  if (day == null) return formatClockTime(local);
  if (calendarDaysBetween(local, now.toLocal()) < 7) {
    return '$day ${formatClockTime(local)}';
  }
  return day;
}
