import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart'
    show ActivitySlab;
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_display.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/blocked_import_parts.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Review of the downloads one arr's connection finished and would not
/// import: what Needs you's `Review 18` opens.
///
/// Under the title, why the arr stopped in a sentence, and `Why?` with the
/// arr's own words and the same in plain ones. Then the files in two parts:
/// those the arr would take as they are, selected (`12 clear matches`), and
/// those that need the user (`6 need you`), each with the choice it needs. A
/// selector jumps between the two. The bar says what stays for later, that
/// an import cannot be undone, and imports what is chosen; the page then goes
/// back to where it was opened, where the import reports itself.
class BlockedImportReviewPage extends ConsumerStatefulWidget {
  const BlockedImportReviewPage({
    super.key,
    required this.service,
    this.instanceId,
  });

  final ServiceKey service;

  /// The connection the route named (`?i=`); null for the lens.
  final String? instanceId;

  @override
  ConsumerState<BlockedImportReviewPage> createState() =>
      _BlockedImportReviewPageState();
}

enum _Part { clear, needYou }

class _BlockedImportReviewPageState
    extends ConsumerState<BlockedImportReviewPage> {
  final _scroll = ScrollController();
  final _clearKey = GlobalKey();
  final _needYouKey = GlobalKey();
  _Part _part = _Part.clear;
  bool _whyOpen = false;

  /// The Need you row that is open, by path.
  String? _open;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_follow);
    Future.microtask(_read);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _read() => ref
      .read(manualImportFlowProvider.notifier)
      .startBlocked(widget.service, instanceId: widget.instanceId);

  /// The selector follows the list: Need you once its heading reaches the
  /// top.
  void _follow() {
    final box = _needYouKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final reveal = viewport.getOffsetToReveal(box, 0).offset;
    final next = _scroll.offset >= reveal - AppSpacing.xxl
        ? _Part.needYou
        : _Part.clear;
    if (next != _part) setState(() => _part = next);
  }

  void _jump(_Part part) {
    setState(() => _part = part);
    final target =
        (part == _Part.clear ? _clearKey : _needYouKey).currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppAnimation.durationLg,
      curve: AppAnimation.standardCurve,
    );
  }

  Future<void> _import() async {
    final command = await ref
        .read(manualImportFlowProvider.notifier)
        .confirmImport();
    if (!mounted || command == null) return;
    // Back where the Review was opened: the import reports itself there.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(ServiceRoutes.activityNeedsYou);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualImportFlowProvider);
    final service = widget.service;
    final review = state.blocked;
    final read =
        review != null && !state.isLoadingItems && state.service == service;

    final byPath = {for (final item in state.items) item.path: item};
    final needYouPaths = review?.needYouPaths ?? const <String>[];
    final needYou = [for (final path in needYouPaths) ?byPath[path]];
    final waiting = needYouPaths.toSet();
    final clear = [
      for (final item in state.items)
        if (!waiting.contains(item.path)) item,
    ];
    final total = clear.length + needYou.length;

    final Widget body;
    if (!read && state.error == null) {
      body = const _Reading();
    } else if (state.error != null && state.items.isEmpty) {
      body = AppErrorState(
        error: state.error!,
        service: service,
        instanceId: widget.instanceId,
        onRetry: _read,
      );
    } else if (total == 0) {
      body = AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'Nothing to import',
          message:
              '${service.title} has no download waiting for a manual '
              'import.',
        ),
      );
    } else {
      body = _content(state, review!, clear, needYou);
    }

    final selected = state.selectedPaths;
    final pickedClear = clear.where((i) => selected.contains(i.path)).length;
    final picked = needYou.where((i) => selected.contains(i.path)).length;
    final chosen = pickedClear + picked;

    return AmbientScaffold(
      appBar: GlassAppBar(
        title: Text(read && total > 0 ? blockedImportTitle(total) : 'Review'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: body),
            if (read && total > 0)
              BlockedImportBar(
                line: picked > 0
                    ? '$pickedClear clear · $picked picked by you'
                    : needYou.isEmpty
                    ? null
                    : '${needYou.length} left for later',
                label: chosen == 0
                    ? 'Select something to import'
                    : pickedClear == clear.length && picked == 0
                    ? (clear.length == 1
                          ? 'Import 1 clear match'
                          : 'Import ${clear.length} clear matches')
                    : 'Import $chosen selected',
                error: state.items.isEmpty ? null : state.error,
                busy: state.isSubmitting,
                onImport: chosen == 0 || state.isSubmitting ? null : _import,
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    ManualImportFlowState state,
    BlockedImportReview review,
    List<ManualImportItem> clear,
    List<ManualImportItem> needYou,
  ) {
    final service = widget.service;
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final total = clear.length + needYou.length;
    final messages = distinctMessages([
      for (final download in review.downloads) download.message,
    ]);
    final cause = blockedImportCauseOf(messages);
    final titles = {
      for (final item in [...clear, ...needYou])
        if (manualImportGroupTitle(service, item) case final title
            when title != 'Unmatched')
          title,
    };
    final kinds = [
      for (final item in needYou)
        review.needYouKinds[item.path] ?? needYouKindOf(service, item),
    ];
    final plain = blockedImportPlainWords(
      service,
      cause,
      title: titles.length == 1 ? titles.single : null,
      total: total,
      unnamed: kinds.where((kind) => kind != NeedYouKind.refused).length,
    );
    final selected = state.selectedPaths;

    // The clear files under the title each was grabbed for, in their order.
    final groups = <String, List<ManualImportItem>>{};
    for (final item in clear) {
      groups
          .putIfAbsent(manualImportGroupTitle(service, item), () => [])
          .add(item);
    }
    final pickedClear = clear.where((i) => selected.contains(i.path)).length;
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final notifier = ref.read(manualImportFlowProvider.notifier);

    Widget gutter(Widget child, {double top = AppSpacing.md}) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        top,
        AppSpacing.gutter,
        0,
      ),
      child: child,
    );

    return RefreshIndicator(
      onRefresh: _read,
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            gutter(
              Text(
                blockedImportExplanation(service, cause, one: total == 1),
                style: AppType.body.copyWith(color: room.inkSecondary),
              ),
              top: AppSpacing.sm,
            ),
            if (messages.isNotEmpty || plain != null) ...[
              gutter(
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _whyOpen = !_whyOpen),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(
                      _whyOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                    label: Text(
                      'Why?',
                      semanticsLabel: _whyOpen ? 'Hide why' : 'Why?',
                    ),
                  ),
                ),
                top: AppSpacing.sm,
              ),
              if (_whyOpen)
                gutter(
                  BlockedImportWhy(
                    service: service,
                    messages: messages,
                    plain: plain,
                  ),
                  top: AppSpacing.sm,
                ),
            ],
            if (clear.isNotEmpty && needYou.isNotEmpty)
              gutter(
                PageTabs<_Part>(
                  values: _Part.values,
                  selected: _part,
                  labelBuilder: (part) => switch (part) {
                    _Part.clear => 'Clear',
                    _Part.needYou => 'Need you',
                  },
                  countOf: (part) => switch (part) {
                    _Part.clear => (count: clear.length, tone: null),
                    _Part.needYou => (
                      count: needYou.length,
                      tone: StatusTone.warning,
                    ),
                  },
                  semanticLabel: 'Jump to',
                  onSelected: _jump,
                ),
                top: AppSpacing.lg,
              ),
            if (clear.isNotEmpty) ...[
              gutter(
                KeyedSubtree(
                  key: _clearKey,
                  child: BlockedImportPartHeading(
                    title: clear.length == 1
                        ? '1 clear match'
                        : '${clear.length} clear matches',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsetsDirectional.only(end: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: blue,
                          ),
                        ),
                        Text(
                          '$pickedClear of ${clear.length} selected',
                          style: AppType.label.copyWith(color: blue),
                        ),
                      ],
                    ),
                  ),
                ),
                top: AppSpacing.xl,
              ),
              for (final MapEntry(key: title, value: files) in groups.entries)
                gutter(
                  BlockedImportClearGroup(
                    service: service,
                    title: title,
                    files: files,
                    selected: selected,
                    replacing: review.replacing,
                    onToggle: notifier.toggleItem,
                    onAll: notifier.setGroupSelected,
                  ),
                  top: AppSpacing.sm,
                ),
            ],
            if (needYou.isNotEmpty) ...[
              gutter(
                KeyedSubtree(
                  key: _needYouKey,
                  child: BlockedImportPartHeading(
                    title: needYou.length == 1
                        ? '1 needs you'
                        : '${needYou.length} need you',
                    explanation: needYouExplanation(
                      service,
                      kinds,
                      one: needYou.length == 1,
                    ),
                  ),
                ),
                top: AppSpacing.xl,
              ),
              gutter(
                ActivitySlab(
                  children: [
                    for (final (index, item) in needYou.indexed)
                      BlockedImportNeedYouRow(
                        key: ValueKey(item.path),
                        service: service,
                        item: item,
                        kind: kinds[index],
                        selected: selected.contains(item.path),
                        divided: index > 0,
                        open: _open == item.path,
                        onOpen: () => setState(
                          () => _open = _open == item.path ? null : item.path,
                        ),
                        onPlaced: () => setState(() => _open = null),
                      ),
                  ],
                ),
                top: AppSpacing.sm,
              ),
            ],
            if (review.leftOut > 0 || review.unread > 0)
              gutter(
                Text(
                  [
                    if (review.leftOut > 0)
                      review.leftOut == 1
                          ? '1 other file stays where it is.'
                          : '${review.leftOut} other files stay where they are.',
                    if (review.unread > 0)
                      review.unread == 1
                          ? "1 download didn't list its files."
                          : "${review.unread} downloads didn't list their "
                                'files.',
                  ].join(' '),
                  style: AppType.meta.copyWith(color: room.inkTertiary),
                ),
                top: AppSpacing.lg,
              ),
          ],
        ),
      ),
    );
  }
}

/// While the arr lists each download's files: the shape of the page to come.
class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            0,
          ),
          child: Text(
            'Reading the files of each download…',
            style: AppType.body.copyWith(color: room.inkSecondary),
          ),
        ),
        AppSkeleton.listRows(count: 5, rowHeight: 64),
      ],
    );
  }
}
