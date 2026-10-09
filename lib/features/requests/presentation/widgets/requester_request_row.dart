/// One of the requester's requests: a row on the Home and on her page, and
/// the card of a request that waits, with its steps and Cancel request.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// A request in a row: the poster, the title, where it stands in her words,
/// the line under it, and the bar while it downloads. One target, to the
/// title's page; one sentence to a screen reader.
///
/// [RequesterRequestRow.home] keeps the state at the row's end, `62%` while
/// it downloads, where the Home's slab has the width for a short word;
/// [RequesterRequestRow.page] puts it under the title with its dot, and a
/// title on the server carries Watch.
class RequesterRequestRow extends StatelessWidget {
  const RequesterRequestRow.home({
    super.key,
    required this.mine,
    required this.now,
    required this.onTap,
    this.divided = false,
  }) : onWatch = null,
       _page = false;

  const RequesterRequestRow.page({
    super.key,
    required this.mine,
    required this.now,
    required this.onTap,
    this.onWatch,
    this.divided = false,
  }) : _page = true;

  final MyRequest mine;
  final DateTime now;
  final VoidCallback onTap;

  /// Opens the title in the player, on a row of her page whose title is on
  /// the server and has Seerr's link to it.
  final VoidCallback? onWatch;

  /// Whether a hairline separates it from the row above.
  final bool divided;

  final bool _page;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(scheme, mine.stage.tone, surface: room.slab);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final progress = mine.progress;
    final title = Text(
      mine.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppType.row.copyWith(color: room.ink),
    );
    final atEnd = !_page && !large;
    final state = _StateWord(
      text: _page ? mine.state : mine.stateShort,
      tone: mine.stage.tone,
      color: tone,
      // A figure at the row's end needs no dot: its colour is the state.
      dot: _page || mine.figure == null,
      align: atEnd ? TextAlign.end : TextAlign.start,
    );
    final detail = Text(
      mine.detail(now),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppType.meta.copyWith(color: room.inkSecondary),
    );
    final bar = progress == null
        ? null
        : HomeRowBar(value: progress, color: tone);

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_page || large) ...[
          title,
          const SizedBox(height: 2),
          state,
        ] else
          // The state keeps its words whole at the row's end, up to half
          // of it; the title takes the rest.
          LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.55),
                  child: state,
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xxs),
        if (bar != null && !_page) ...[
          const SizedBox(height: AppSpacing.xs),
          bar,
          const SizedBox(height: AppSpacing.xs),
        ],
        detail,
        if (bar != null && _page) ...[
          const SizedBox(height: AppSpacing.sm),
          bar,
        ],
      ],
    );
    final watch = onWatch;
    // The row is one sentence and one target; Watch is a target of its own
    // beside it, at the end of the row or, at a large reading size, under
    // the words.
    final row = Semantics(
      container: true,
      button: true,
      label: mine.spoken(now),
      excludeSemantics: true,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Poster(mine: mine, large: _page),
          const SizedBox(width: AppSpacing.row),
          Expanded(child: words),
        ],
      ),
    );
    final watchButton = watch == null
        ? null
        : Semantics(
            button: true,
            label: 'Watch ${mine.title}',
            excludeSemantics: true,
            onTap: watch,
            child: _WatchButton(onTap: watch),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided
            ? Border(top: BorderSide(color: room.hair))
            : const Border(),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusSm,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: _page ? AppSpacing.md : AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: row),
                  if (watchButton != null && !large) ...[
                    const SizedBox(width: AppSpacing.sm),
                    watchButton,
                  ],
                ],
              ),
              if (watchButton != null && large) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: watchButton),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A request that waits for an answer, on her page: the poster, the title,
/// `Waiting for approval`, when she asked, the three steps it goes through,
/// and [cancel], the one thing she may do.
class RequesterWaitingCard extends StatelessWidget {
  const RequesterWaitingCard({
    super.key,
    required this.mine,
    required this.now,
    required this.onTap,
    required this.cancel,
  });

  final MyRequest mine;
  final DateTime now;

  /// The title's page.
  final VoidCallback onTap;

  /// Cancel request, as the gate draws it.
  final Widget cancel;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(scheme, mine.stage.tone, surface: room.slab);
    final asked = switch (mine.askedAt) {
      final at? => _capitalized(askedWords(at, now: now)),
      null => null,
    };
    return Container(
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: BorderRadius.circular(AppRadius.slab),
        border: Border.all(color: room.hair),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            button: true,
            label:
                "${mine.spoken(now)}. Next, approval by the server's owner, "
                'then ready to watch.',
            excludeSemantics: true,
            onTap: onTap,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.borderRadiusSm,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Poster(mine: mine, large: true, card: true),
                  const SizedBox(width: AppSpacing.row),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          mine.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.section.copyWith(color: room.ink),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _StateWord(
                          text: mine.state,
                          tone: mine.stage.tone,
                          color: tone,
                          dot: true,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mine.detail(now),
                          style: AppType.meta.copyWith(
                            color: room.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ExcludeSemantics(
            child: _Steps(tone: tone, asked: asked),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(alignment: Alignment.centerRight, child: cancel),
        ],
      ),
    );
  }
}

/// Asked, approval, ready to watch: the first done, the second the one it
/// waits on, the third ahead.
class _Steps extends StatelessWidget {
  const _Steps({required this.tone, required this.asked});

  final Color tone;
  final String? asked;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget label(
      String text,
      Color color, {
      TextAlign align = TextAlign.center,
    }) => Text(
      text,
      textAlign: align,
      style: AppType.meta.weight(FontWeight.w600).copyWith(color: color),
    );
    Widget under(String? text, {TextAlign align = TextAlign.center}) =>
        text == null
        ? const SizedBox.shrink()
        : Text(
            text,
            textAlign: align,
            style: AppType.caption.copyWith(color: room.inkSecondary),
          );
    // At a large reading size the steps go one under the other: three
    // columns would break their words.
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      Widget step(Widget mark, Widget words) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 4), child: mark),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: words),
          ],
        ),
      );
      Widget words(String title, Color color, String? line) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(title, color, align: TextAlign.start),
          under(line, align: TextAlign.start),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          step(_StepMark.done(color: tone), words('Asked', room.ink, asked)),
          step(
            _StepMark.current(color: tone),
            words('Approval', tone, "By the server's owner"),
          ),
          step(
            _StepMark.ahead(color: room.inkTertiary),
            words('Ready to watch', room.inkSecondary, null),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: Row(
            children: [
              _StepMark.done(color: tone),
              Expanded(child: _StepLine(color: tone)),
              _StepMark.current(color: tone),
              Expanded(child: _StepLine.ahead(color: room.inkTertiary)),
              _StepMark.ahead(color: room.inkTertiary),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Asked', room.ink, align: TextAlign.start),
                  under(asked, align: TextAlign.start),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  label('Approval', tone),
                  under("By the server's owner"),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  label(
                    'Ready to watch',
                    room.inkSecondary,
                    align: TextAlign.end,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark.done({required this.color}) : _kind = 0;
  const _StepMark.current({required this.color}) : _kind = 1;
  const _StepMark.ahead({required this.color}) : _kind = 2;

  final Color color;
  final int _kind;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (_kind) {
          0 => color,
          1 => room.slab,
          _ => room.fillStrong,
        },
        border: _kind == 1 ? Border.all(color: color, width: 2) : null,
      ),
      child: switch (_kind) {
        0 => Icon(Icons.check_rounded, size: 14, color: room.slab),
        1 => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        _ => null,
      },
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.color}) : _dashed = false;
  const _StepLine.ahead({required this.color}) : _dashed = true;

  final Color color;
  final bool _dashed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 2,
    child: _dashed
        ? CustomPaint(painter: _Dashes(color: color))
        : ColoredBox(color: color),
  );
}

class _Dashes extends CustomPainter {
  const _Dashes({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    const dash = 5.0;
    const gap = 4.0;
    for (var x = gap; x < size.width - gap; x += dash + gap) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dash).clamp(0, size.width - gap), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

/// Where a request stands, in its tone: a dot before the word, hollow for
/// an answer.
class _StateWord extends StatelessWidget {
  const _StateWord({
    required this.text,
    required this.tone,
    required this.color,
    required this.dot,
    this.align = TextAlign.start,
  });

  final String text;
  final StatusTone tone;
  final Color color;
  final bool dot;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final neutral = tone == StatusTone.neutral;
    final room = CupolaRoom.of(context);
    final ink = neutral ? room.inkSecondary : color;
    // The dot rides the first line, where the word starts, however many
    // lines the word takes: centred on a line of `meta` at this reading size.
    final line = MediaQuery.textScalerOf(
      context,
    ).scale(AppType.meta.fontSize! * (AppType.meta.height ?? 1));
    final words = Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: AppType.meta.weight(FontWeight.w600).copyWith(color: ink),
    );
    if (!dot) return words;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: (line - 7) / 2),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: neutral ? null : color,
              border: neutral ? Border.all(color: ink, width: 1.2) : null,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Flexible(child: words),
      ],
    );
  }
}

/// The poster: 36×54 in the Home's row, 52×78 on her page, 68×100 on the
/// card of a request that waits.
class _Poster extends StatelessWidget {
  const _Poster({required this.mine, required this.large, this.card = false});

  final MyRequest mine;
  final bool large;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final path = mine.request.media?.posterPath;
    final url = ImageUtils.buildTmdbPosterUrl(path, size: 'w185');
    if (!large) {
      return HomeRowArt(posterUrl: url, icon: Icons.movie_outlined);
    }
    final width = card ? 68.0 : 52.0;
    final room = CupolaRoom.of(context);
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: url.isEmpty
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: room.fillQuiet,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Icon(
                Icons.movie_outlined,
                size: 20,
                color: room.inkSecondary,
              ),
            )
          : ContentCard(imageUrl: url),
    );
  }
}

/// Watch, quiet, at the end of a row whose title is on the server.
class _WatchButton extends StatelessWidget {
  const _WatchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final height = TextScaleMetrics.boxHeight(
      context,
      base: 44,
      textHeight: 18,
    );
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.standard,
        minimumSize: Size(88, height),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 18),
      label: const Text('Watch'),
    );
  }
}

String _capitalized(String words) =>
    words.isEmpty ? words : '${words[0].toUpperCase()}${words.substring(1)}';
