import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/activity/domain/download_table.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart'
    show hasArrRecord;
import 'package:cupola/features/activity/presentation/download_actions.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart'
    show RowAction, SelectedRowPainter, showRowActions;
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/inspector_state.dart';

/// The table's order, kept while the app runs, the same on All and on
/// Downloads: a choice of the moment, never written down.
class _DownloadSortNotifier extends Notifier<DownloadSort?> {
  @override
  DownloadSort? build() => null;

  void sortBy(DownloadColumn column) => state = nextDownloadSort(state, column);
}

final _downloadSortProvider =
    NotifierProvider<_DownloadSortNotifier, DownloadSort?>(
      _DownloadSortNotifier.new,
    );

/// The Progress column: the figure, and the bar under it.
const double _progressWidth = 150;
const double _speedWidth = 84;
const double _leftWidth = 96;

/// Room for Stop on the row under the pointer, and its ⋯.
const double _trailWidth = 80;
const double _gap = AppSpacing.lg;

/// Downloads as a desktop window reads them: a table of Title, Progress,
/// Speed and Left, sortable by each from its header, a row a download.
///
/// A click chooses a download and the inspector shows it (`Selected
/// download`); a second click on the chosen row, or Return, opens its page;
/// the arrow keys walk the rows, choosing as they go, and Escape lets go. The
/// row under the pointer offers Stop (Resume once stopped); its ⋯ and a
/// secondary click offer Open, Stop and Remove. In a compact window the
/// inspector is not laid out: Speed and Left join the line under the title,
/// and a click opens the page, as on a phone.
class DownloadTable extends ConsumerStatefulWidget {
  const DownloadTable({
    super.key,
    required this.items,
    required this.now,
    this.requests = const [],
  }) : _queued = false;

  /// Up next: the downloads waiting their turn, in the order they will
  /// start, under no header of their own: `Queued · starts in about 6 min`
  /// across Progress, Speed and Left.
  const DownloadTable.queued({
    super.key,
    required this.items,
    required this.now,
    this.requests = const [],
  }) : _queued = true;

  final List<ServiceQueueItem> items;

  /// The clock `around 21:10` and `nothing for 3 h` are read by.
  final DateTime now;

  /// The household's requests, for who asked for each ([requestFor]).
  final List<SeerrRequest> requests;

  final bool _queued;

  @override
  ConsumerState<DownloadTable> createState() => _DownloadTableState();
}

class _DownloadTableState extends ConsumerState<DownloadTable> {
  /// The row clicked last, and when: a second click on it soon after opens
  /// its page.
  (DownloadSelection, DateTime)? _lastClick;

  /// The rows whose Stop or Resume is on its way.
  final Set<String> _busy = {};

  @override
  Widget build(BuildContext context) {
    final compact = AppBreakpoints.isCompactDesktop(context);
    // At a large reading size the figures' columns would break their words:
    // they join the line under the title, as in a compact window.
    final narrow = compact || MediaQuery.textScalerOf(context).scale(10) >= 13;
    final sort = widget._queued ? null : ref.watch(_downloadSortProvider);
    final rows = sortDownloads(widget.items, sort);
    final selection = ref.watch(selectedDownloadProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget._queued)
          _Header(
            compact: narrow,
            sort: sort,
            onSort: ref.read(_downloadSortProvider.notifier).sortBy,
          ),
        for (final (index, item) in rows.indexed)
          _Row(
            key: ValueKey('${item.service}-${item.instanceId}-${item.id}'),
            item: item,
            now: widget.now,
            request: requestFor(item, widget.requests),
            compact: narrow,
            choosing: !compact,
            queued: widget._queued,
            divided: index > 0 || !widget._queued,
            selected: !compact && isSelectedDownload(selection, item),
            busy: _busy.contains(downloadPageKey(item)),
            onClick: () => _click(item, compact: compact),
            onFocused: () {
              if (!compact) _choose(item);
            },
            onOpen: () => context.openDownload(item),
            onLetGo: () => ref.read(selectedDownloadProvider.notifier).clear(),
            onStop: canStopDownload(item) ? () => _stop(item) : null,
            onRemove: hasArrRecord(item) && item.fault == null
                ? () => _remove(item)
                : null,
          ),
      ],
    );
  }

  /// A click: in a full window, chooses [item] for the inspector, and on the
  /// chosen row soon after the last click, opens its page; in a compact one,
  /// opens the page.
  void _click(ServiceQueueItem item, {required bool compact}) {
    if (compact) {
      context.openDownload(item);
      return;
    }
    final chosen = selectionOf(item);
    final now = DateTime.now();
    final last = _lastClick;
    _lastClick = (chosen, now);
    if (last != null &&
        last.$1 == chosen &&
        now.difference(last.$2) <= _doubleClick) {
      _lastClick = null;
      context.openDownload(item);
      return;
    }
    _choose(item);
  }

  void _choose(ServiceQueueItem item) {
    ref.read(selectedDownloadProvider.notifier).select(item);
    ref.read(inspectorStateProvider.notifier).setOpen(true);
  }

  Future<void> _stop(ServiceQueueItem item) async {
    final key = downloadPageKey(item);
    setState(() => _busy.add(key));
    await stopDownload(context, ref, item, stop: !item.held);
    if (mounted) setState(() => _busy.remove(key));
  }

  Future<void> _remove(ServiceQueueItem item) async {
    final removed = await removeDownload(context, ref, item);
    if (!removed || !mounted) return;
    if (isSelectedDownload(ref.read(selectedDownloadProvider), item)) {
      ref.read(selectedDownloadProvider.notifier).clear();
    }
  }
}

/// How soon a second click on a chosen row opens it: the platform's double
/// click.
const Duration _doubleClick = kDoubleTapTimeout;

/// The header: each column's name, which sorts the table by it, the chosen
/// one in the ink with its arrow.
class _Header extends StatelessWidget {
  const _Header({
    required this.compact,
    required this.sort,
    required this.onSort,
  });

  final bool compact;
  final DownloadSort? sort;
  final ValueChanged<DownloadColumn> onSort;

  @override
  Widget build(BuildContext context) {
    Widget cell(DownloadColumn column) =>
        _HeaderCell(column: column, sort: sort, onSort: onSort);
    return Padding(
      padding: const EdgeInsets.only(left: HomeRowArt.width + AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: cell(DownloadColumn.title),
            ),
          ),
          const SizedBox(width: _gap),
          SizedBox(width: _progressWidth, child: cell(DownloadColumn.progress)),
          if (!compact) ...[
            const SizedBox(width: _gap),
            SizedBox(width: _speedWidth, child: cell(DownloadColumn.speed)),
            const SizedBox(width: _gap),
            SizedBox(width: _leftWidth, child: cell(DownloadColumn.left)),
          ],
          const SizedBox(width: _trailWidth),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.sort,
    required this.onSort,
  });

  final DownloadColumn column;
  final DownloadSort? sort;
  final ValueChanged<DownloadColumn> onSort;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final sort = this.sort;
    final active = sort != null && sort.column == column;
    final color = active ? room.ink : room.inkSecondary;
    final style = AppType.meta.copyWith(color: color);
    final order = !active
        ? null
        : sort.descending
        ? 'sorted, highest first'
        : 'sorted, lowest first';
    return Semantics(
      button: true,
      label: column.label,
      value: order,
      hint: 'Sorts by ${column.label.toLowerCase()}',
      excludeSemantics: true,
      onTap: () => onSort(column),
      child: InkWell(
        onTap: () => onSort(column),
        borderRadius: AppRadius.borderRadiusSm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: active ? style.weight(FontWeight.w600) : style,
                ),
              ),
              if (active) ...[
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  sort.descending
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 14,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One download, a row of the table: one sentence to a screen reader, the
/// whole row a target.
class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.item,
    required this.now,
    required this.request,
    required this.compact,
    required this.choosing,
    required this.queued,
    required this.divided,
    required this.selected,
    required this.busy,
    required this.onClick,
    required this.onFocused,
    required this.onOpen,
    required this.onLetGo,
    required this.onStop,
    required this.onRemove,
  });

  final ServiceQueueItem item;
  final DateTime now;
  final SeerrRequest? request;

  /// Whether Speed and Left join the line under the title.
  final bool compact;

  /// Whether a click chooses the row for the inspector (a full window), or
  /// opens its page.
  final bool choosing;
  final bool queued;
  final bool divided;
  final bool selected;
  final bool busy;
  final VoidCallback onClick;
  final VoidCallback onFocused;
  final VoidCallback onOpen;
  final VoidCallback onLetGo;
  final VoidCallback? onStop;
  final VoidCallback? onRemove;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;
  Offset? _pressedAt;

  List<RowAction> get _actions {
    final item = widget.item;
    final stop = widget.onStop;
    final remove = widget.onRemove;
    return [
      (
        label: 'Open download',
        icon: Icons.open_in_new_rounded,
        onSelected: widget.onOpen,
      ),
      if (stop != null && !widget.busy)
        item.held
            ? (
                label: 'Resume',
                icon: Icons.play_arrow_rounded,
                onSelected: stop,
              )
            : (label: 'Stop', icon: Icons.stop_rounded, onSelected: stop),
      if (remove != null)
        (
          label: 'Remove',
          icon: Icons.delete_outline_rounded,
          onSelected: remove,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final progress = downloadProgressCell(item);
    final tone = statusToneColor(scheme, progress.tone, surface: room.slab);
    final speed = downloadSpeedCell(item);
    final left = downloadLeftCell(item, now: widget.now);
    final route = downloadRouteLine(
      item,
      request: widget.request,
      now: widget.now,
      withFigures: widget.compact,
    );
    final release = item.names.machineName;
    final showsRelease =
        release != null && release.isNotEmpty && release != item.title;
    final actions = _actions;
    final value = [
      spokenPercents(progress.text),
      route,
      if (!widget.compact && speed != Lexicon.noFigure)
        spokenBytesPerSecond(speed),
      if (!widget.compact && left.around != null)
        '${left.left} left, ready ${left.around}',
    ].join(', ');

    final figures = AppType.meta.tabular.copyWith(color: room.ink);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.row.copyWith(color: room.ink),
        ),
        if (showsRelease)
          Text(
            release,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: AppType.mono.copyWith(color: room.inkSecondary),
          ),
        Text(
          route,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta.copyWith(color: room.inkSecondary),
        ),
      ],
    );
    final progressCell = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          progress.text,
          maxLines: 2,
          style: AppType.meta
              .weight(FontWeight.w600)
              .tabular
              .copyWith(color: tone),
        ),
        if (!widget.queued)
          if (item.progress case final value?) ...[
            const SizedBox(height: AppSpacing.xs),
            HomeRowBar(value: value, color: tone),
          ],
      ],
    );
    final trail = SizedBox(
      width: _trailWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_hovered && widget.onStop != null)
            _RowButton(
              icon: item.held ? Icons.play_arrow_rounded : Icons.stop_rounded,
              tooltip: item.held
                  ? 'Resume · picks up where it stopped'
                  : 'Stop · keeps what has arrived',
              onPressed: widget.busy ? null : widget.onStop,
            ),
          Builder(
            builder: (context) => _RowButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'More',
              onPressed: () {
                final box = context.findRenderObject() as RenderBox?;
                showRowActions(
                  context,
                  box?.localToGlobal(box.size.bottomLeft(Offset.zero)),
                  actions,
                );
              },
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      // Over the row and its buttons alike, so Stop stays while the pointer
      // moves onto it.
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: widget.divided
              ? Border(top: BorderSide(color: room.hair))
              : null,
        ),
        child: Stack(
          children: [
            Semantics(
              container: true,
              button: true,
              selected: widget.selected,
              label: item.title,
              value: value,
              hint: widget.choosing ? 'Shows it in the inspector' : null,
              onTap: widget.onClick,
              customSemanticsActions: {
                for (final action in actions)
                  CustomSemanticsAction(label: action.label): action.onSelected,
              },
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): _OpenIntent(),
                  SingleActivator(LogicalKeyboardKey.numpadEnter):
                      _OpenIntent(),
                  SingleActivator(LogicalKeyboardKey.escape): _LetGoIntent(),
                },
                child: Actions(
                  actions: {
                    _OpenIntent: CallbackAction<_OpenIntent>(
                      onInvoke: (_) {
                        widget.onOpen();
                        return null;
                      },
                    ),
                    _LetGoIntent: CallbackAction<_LetGoIntent>(
                      onInvoke: (_) {
                        widget.onLetGo();
                        return null;
                      },
                    ),
                  },
                  child: InkWell(
                    onTap: widget.onClick,
                    onFocusChange: (focused) {
                      // Walking the rows with the keys chooses as it goes; a
                      // click chooses on its own.
                      if (focused &&
                          FocusManager.instance.highlightMode ==
                              FocusHighlightMode.traditional) {
                        widget.onFocused();
                      }
                    },
                    onSecondaryTapDown: (details) =>
                        _pressedAt = details.globalPosition,
                    onSecondaryTap: () =>
                        showRowActions(context, _pressedAt, actions),
                    borderRadius: AppRadius.borderRadiusMd,
                    excludeFromSemantics: true,
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        painter: widget.selected
                            ? SelectedRowPainter(room.fillStrong)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.row,
                          ),
                          child: Row(
                            children: [
                              HomeRowArt(
                                posterUrl: item.posterUrl,
                                icon: item.service.icon,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(child: title),
                              const SizedBox(width: _gap),
                              SizedBox(
                                width: widget.queued && !widget.compact
                                    ? _progressWidth +
                                          _speedWidth +
                                          _leftWidth +
                                          2 * _gap
                                    : _progressWidth,
                                child: progressCell,
                              ),
                              if (!widget.compact && !widget.queued) ...[
                                const SizedBox(width: _gap),
                                SizedBox(
                                  width: _speedWidth,
                                  child: Text(speed, style: figures),
                                ),
                                const SizedBox(width: _gap),
                                SizedBox(
                                  width: _leftWidth,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(left.left, style: figures),
                                      if (left.around case final around?)
                                        Text(
                                          around,
                                          maxLines: 1,
                                          style: AppType.caption.tabular
                                              .copyWith(
                                                color: room.inkTertiary,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              // The buttons lie over the row, not in it.
                              const SizedBox(width: _trailWidth),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Over the row rather than inside its target, so a click on Stop
            // or ⋯ is theirs and never the row's.
            Positioned(top: 0, bottom: 0, right: 0, child: trail),
          ],
        ),
      ),
    );
  }
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _LetGoIntent extends Intent {
  const _LetGoIntent();
}

/// A 36 × 44 icon control at the row's end, in the secondary ink.
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon, size: 18),
    color: CupolaRoom.of(context).inkSecondary,
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.standard,
    constraints: const BoxConstraints.tightFor(width: 36, height: 44),
  );
}
