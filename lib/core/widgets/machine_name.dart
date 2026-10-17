import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';

/// Which machine name a [MachineName] carries. It decides the words of the
/// copy action, which is the one place the two kinds differ.
enum _MachineNameKind {
  file(copyLabel: 'Copy file name', spokenLabel: 'File name'),
  release(copyLabel: 'Copy release name', spokenLabel: 'Release name');

  const _MachineNameKind({required this.copyLabel, required this.spokenLabel});

  /// The verb, everywhere it is offered: the screen-reader action, the
  /// desktop context menu and the copy button's tooltip.
  final String copyLabel;

  /// What an in-full name is called when the caller gives it no caption.
  final String spokenLabel;
}

/// Where a [MachineName] sits: under a row's title, beside the subject of a
/// detail card, or as that subject.
enum _MachineNameShape { row, title, inFull, lead }

/// The exact string of an object on disk or in a download, drawn as it came.
///
/// A title says *what* a thing is; a machine name says *which copy*: the file
/// in the library, the torrent, the NZB. It is set in Geist Mono
/// ([AppType.mono]) and is never rewritten: no dots turned into spaces, no
/// year cut off. A cleaned-up name looks like a title and is wrong with
/// confidence.
///
/// Seven variants, as named constructors:
///
/// * [MachineName.file] and [MachineName.release] sit under a row's title. One
///   line, with the ellipsis **in the middle**, because the front says what the
///   copy is and the back (the group and the extension) says which one, and an
///   ellipsis at the end deletes the half that answers "is this the right
///   file?". The extension is always kept whole. On a desktop the full name
///   shows on hover.
/// * [MachineName.fileTitle] is the same row, in the ink, for a row whose
///   title *is* the file: a file the service could not match, which has no
///   other name to lead with.
/// * [MachineName.fileLead] and [MachineName.releaseLead] are the subject of
///   a detail card, in the ink, as a card's title is: the File card of a movie,
///   whose page title already says *what* and whose card says *which copy*.
///   The whole name, wrapping after its dots, selectable, with a copy button.
/// * [MachineName.fileInFull] and [MachineName.releaseInFull] are the same in
///   full form beside that subject, secondary: what the file was released as.
///
/// A row's name and a secondary name are in the tertiary ink; only a lead and
/// a file title take the ink.
///
/// Copying is the same gesture everywhere: a long press on a phone, the
/// context menu on a desktop, the copy button in full, and a custom
/// screen-reader action named for what is copied (*Copy file name*, *Copy
/// release name*). Each one copies the name exactly and confirms with the
/// toast *Copied*.
///
/// Semantics: in a row the name is **not** part of the row's sentence. Read
/// aloud it is unlistenable and it repeats the title, so the row variants
/// exclude their text and contribute only the copy action, which merges into
/// the row's node. A host must therefore not wrap this widget in
/// `ExcludeSemantics`, or the action goes with it. A row that has to silence
/// its whole subtree (a card that speaks one composed sentence) passes
/// [fileCopyActions] or [releaseCopyActions] to its own node instead
/// (`AppCard.customSemanticsActions`, or the `customSemanticsActions` of a
/// bare `Semantics`), and the action lands on the node the row speaks from.
/// In full, the name is its own
/// node, read whole after its label (the [caption], or *File name* / *Release
/// name*), and the copy button is a sibling node.
class MachineName extends StatefulWidget {
  /// A file name under a row's title: one line, the ellipsis in the middle.
  const MachineName.file(this.name, {super.key})
    : caption = null,
      _kind = _MachineNameKind.file,
      _shape = _MachineNameShape.row;

  /// A file name that is the title of its row, in the ink: one line, the
  /// ellipsis in the middle.
  const MachineName.fileTitle(this.name, {super.key})
    : caption = null,
      _kind = _MachineNameKind.file,
      _shape = _MachineNameShape.title;

  /// A release name (a torrent, an NZB, a grabbed release) under a row's
  /// title: one line, the ellipsis in the middle.
  const MachineName.release(this.name, {super.key})
    : caption = null,
      _kind = _MachineNameKind.release,
      _shape = _MachineNameShape.row;

  /// A file name that is the subject of its detail card: in the ink, whole,
  /// wrapping, selectable, with a copy button.
  const MachineName.fileLead(this.name, {super.key})
    : caption = null,
      _kind = _MachineNameKind.file,
      _shape = _MachineNameShape.lead;

  /// A release name that is the subject of its detail card: in the ink,
  /// whole, wrapping, selectable, with a copy button.
  const MachineName.releaseLead(this.name, {super.key})
    : caption = null,
      _kind = _MachineNameKind.release,
      _shape = _MachineNameShape.lead;

  /// A file name beside the subject of a detail card, in the tertiary ink:
  /// whole, wrapping, selectable, with a copy button.
  const MachineName.fileInFull(this.name, {super.key, this.caption})
    : _kind = _MachineNameKind.file,
      _shape = _MachineNameShape.inFull;

  /// A release name beside the subject of a detail card, in the tertiary ink:
  /// whole, wrapping, selectable, with a copy button. The File section passes
  /// `caption: 'Released as'` under the file it names.
  const MachineName.releaseInFull(this.name, {super.key, this.caption})
    : _kind = _MachineNameKind.release,
      _shape = _MachineNameShape.inFull;

  /// The copy action of a file name, for a host that silences its subtree and
  /// so cannot take it from the widget: *Copy file name*, copying [name]
  /// exactly and confirming with the toast *Copied*.
  static Map<CustomSemanticsAction, VoidCallback> fileCopyActions(
    BuildContext context,
    String name,
  ) => _copyActions(context, name, _MachineNameKind.file);

  /// The copy action of a release name: *Copy release name*. See
  /// [fileCopyActions].
  static Map<CustomSemanticsAction, VoidCallback> releaseCopyActions(
    BuildContext context,
    String name,
  ) => _copyActions(context, name, _MachineNameKind.release);

  /// The string, exactly as the service returned it.
  final String name;

  /// [MachineName.fileInFull] and [MachineName.releaseInFull] only: the words
  /// drawn ahead of the name, in the text face, and read before it
  /// (*Released as*). Null draws nothing ahead of the name and
  /// reads it after *File name* or *Release name*.
  final String? caption;

  final _MachineNameKind _kind;
  final _MachineNameShape _shape;

  @override
  State<MachineName> createState() => _MachineNameState();
}

Map<CustomSemanticsAction, VoidCallback> _copyActions(
  BuildContext context,
  String name,
  _MachineNameKind kind,
) => {
  CustomSemanticsAction(label: kind.copyLabel): () async {
    await Clipboard.setData(ClipboardData(text: name));
    if (!context.mounted) return;
    SnackBarHelper.info(context, 'Copied');
  },
};

class _MachineNameState extends State<MachineName> {
  /// The elided form per available width, for the style and scale it was
  /// measured in. A row rebuilds on every scroll frame of its list, and a
  /// bisection is a dozen text layouts: measured once per width, not per frame.
  final Map<double, String> _fitted = {};
  Object? _fittedFor;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.name));
    if (!mounted) return;
    SnackBarHelper.info(context, 'Copied');
  }

  void _copyFromLongPress() {
    Feedback.forLongPress(context);
    _copy();
  }

  Future<void> _showContextMenu(TapUpDetails details) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final copy = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<bool>(value: true, child: Text(widget._kind.copyLabel)),
      ],
    );
    if (copy == true) await _copy();
  }

  Map<CustomSemanticsAction, VoidCallback> get _semanticsActions => {
    CustomSemanticsAction(label: widget._kind.copyLabel): _copy,
  };

  /// The ink for a lead, the tertiary ink for everything else: a name under
  /// a row's title, and a name beside a card's subject.
  TextStyle _nameStyle(BuildContext context) => AppType.mono.copyWith(
    color:
        widget._shape == _MachineNameShape.lead ||
            widget._shape == _MachineNameShape.title
        ? Theme.of(context).colorScheme.onSurface
        : CupolaThemeColors.of(context).dimText,
  );

  @override
  Widget build(BuildContext context) {
    final style = _nameStyle(context);
    return widget._shape == _MachineNameShape.row ||
            widget._shape == _MachineNameShape.title
        ? _buildRow(context, style)
        : _buildInFull(context, style);
  }

  Widget _buildRow(BuildContext context, TextStyle style) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final key = (widget.name, style, textScaler, textDirection);
    if (key != _fittedFor) {
      _fitted.clear();
      _fittedFor = key;
    }

    return Semantics(
      customSemanticsActions: _semanticsActions,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _copyFromLongPress,
          onSecondaryTapUp: _showContextMenu,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final shown = _fitted[width] ??= elideMachineName(
                widget.name,
                maxWidth: width,
                widthOf: (value) => _measure(
                  value,
                  style: style,
                  textScaler: textScaler,
                  textDirection: textDirection,
                ),
              );
              final line = Text(
                shown,
                maxLines: 1,
                softWrap: false,
                // The elision already fits; this only bites when not even the
                // extension fits, and a second ellipsis would read as part of
                // the name.
                overflow: TextOverflow.clip,
                style: style,
              );
              if (shown == widget.name) return line;
              return Tooltip(
                // A pointer's hover only: on a touch screen the long press
                // belongs to copying.
                triggerMode: TooltipTriggerMode.manual,
                excludeFromSemantics: true,
                richMessage: TextSpan(text: widget.name, style: AppType.mono),
                child: line,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInFull(BuildContext context, TextStyle style) {
    final theme = Theme.of(context);
    final caption = widget.caption;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            label: caption ?? widget._kind.spokenLabel,
            value: widget.name,
            customSemanticsActions: _semanticsActions,
            child: ExcludeSemantics(
              child: _SelectableMachineName(
                name: widget.name,
                caption: caption,
                style: style,
                captionStyle: theme.textTheme.bodySmall?.copyWith(
                  color: CupolaThemeColors.of(context).dimText,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _copy,
          tooltip: widget._kind.copyLabel,
          color: theme.colorScheme.onSurfaceVariant,
          icon: const Icon(Icons.copy_rounded, size: 18),
        ),
      ],
    );
  }
}

double _measure(
  String value, {
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Separators that would collide with the ellipsis and read as a run of dots:
/// `Next.…264` looks like `Next.....264`.
final _trailingSeparators = RegExp(r'[._\-\s]+$');
final _leadingSeparators = RegExp(r'^[._\-\s]+');

/// A file extension: a dot and up to eight letters or digits at the very end.
/// A release name without one (`…x264-GROUP`) has none, because the dash is
/// not part of an extension.
final _extension = RegExp(r'\.[A-Za-z0-9]{1,8}$');

/// The longest form of [name] that fits [maxWidth] with the ellipsis in the
/// middle, keeping as many characters of the front as of the back, and the
/// extension whole.
///
/// [widthOf] measures a candidate in the style it will be drawn in. The kept
/// count is bisected rather than guessed: a fixed character budget is right at
/// one reading size and wrong at every other. When not even an ellipsis and the
/// extension fit, that is what is returned, and the line clips.
@visibleForTesting
String elideMachineName(
  String name, {
  required double maxWidth,
  required double Function(String value) widthOf,
}) {
  if (!maxWidth.isFinite || widthOf(name) <= maxWidth) return name;

  final characters = name.characters.toList(growable: false);
  final extensionMatch = _extension.firstMatch(name);
  final extension = extensionMatch == null || extensionMatch.start == 0
      ? ''
      : extensionMatch.group(0)!;
  final extensionLength = extension.characters.length;
  if (characters.length <= extensionLength + 1) return name;

  String candidate(int kept) {
    final back = math.max(extensionLength, kept ~/ 2);
    final front = math.max(0, kept - back);
    final head = characters
        .take(front)
        .join()
        .replaceFirst(_trailingSeparators, '');
    final tail = characters.skip(characters.length - back).join();
    final body = tail
        .substring(0, tail.length - extension.length)
        .replaceFirst(_leadingSeparators, '');
    return '$head…$body$extension';
  }

  var low = extensionLength;
  var high = characters.length - 1;
  if (widthOf(candidate(low)) > maxWidth) return candidate(low);
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (widthOf(candidate(mid)) <= maxWidth) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return candidate(low);
}

const _zeroWidthSpace = '\u200B';

/// [name] with a line-break opportunity after every dot and underscore but the
/// extension's.
///
/// A release name is one unbroken word to the line breaker: a dot between
/// letters is not a break, so `Coffee.Run.2020.1080p` would break wherever the
/// line ran out, mid-segment. A zero-width space after each separator lets it
/// wrap after its dots, as the brand book asks. The extension stays on the
/// segment before it, as it stays whole in a row: a line of its own reading
/// `mkv` says nothing. The space is drawn but never copied:
/// [_SelectableMachineName] strips it from anything it puts on the clipboard.
///
/// Also what a fact drawn whole uses for its machine's string (a download's
/// release on its page), which no one copies from.
String machineNameWithBreaks(String name) {
  // A name that already carries one cannot be told apart from the inserted
  // ones on the way back out, so it is drawn as it came.
  if (name.contains(_zeroWidthSpace)) return name;
  final extensionAt = _extension.firstMatch(name)?.start;
  return name.replaceAllMapped(
    RegExp(r'[._](?=.)'),
    (match) =>
        match.start == extensionAt ? match[0]! : '${match[0]}$_zeroWidthSpace',
  );
}

/// The in-full name: selectable, wrapping after its dots, and copied exactly.
///
/// The break opportunities are characters in the drawn text, so a plain
/// `SelectableText` would put them on the clipboard and a pasted name would no
/// longer match the file it names. Both ways out of a selection are taken
/// over: the keyboard's copy (an override of the overridable
/// [CopySelectionTextIntent] action) and the toolbar's, which keeps only Copy
/// and Select all. Share, Look up and Search would hand the drawn text to
/// another app.
class _SelectableMachineName extends StatefulWidget {
  const _SelectableMachineName({
    required this.name,
    required this.caption,
    required this.style,
    required this.captionStyle,
  });

  final String name;
  final String? caption;
  final TextStyle style;
  final TextStyle? captionStyle;

  @override
  State<_SelectableMachineName> createState() => _SelectableMachineNameState();
}

class _SelectableMachineNameState extends State<_SelectableMachineName> {
  TextSelection _selection = const TextSelection.collapsed(offset: -1);

  TextSpan get _span => TextSpan(
    children: [
      if (widget.caption != null)
        TextSpan(text: '${widget.caption} ', style: widget.captionStyle),
      TextSpan(text: machineNameWithBreaks(widget.name), style: widget.style),
    ],
  );

  void _copySelection(String text, TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed) return;
    final picked = selection.textInside(text).replaceAll(_zeroWidthSpace, '');
    Clipboard.setData(ClipboardData(text: picked));
  }

  @override
  Widget build(BuildContext context) {
    final span = _span;
    return Actions(
      actions: {
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) {
            _copySelection(span.toPlainText(), _selection);
            return null;
          },
        ),
      },
      child: SelectableText.rich(
        span,
        style: widget.style,
        onSelectionChanged: (selection, cause) => _selection = selection,
        contextMenuBuilder: (context, editableTextState) {
          final value = editableTextState.textEditingValue;
          final items = <ContextMenuButtonItem>[
            for (final item in editableTextState.contextMenuButtonItems)
              if (item.type == ContextMenuButtonType.copy)
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.copy,
                  onPressed: () {
                    _copySelection(value.text, value.selection);
                    editableTextState.hideToolbar();
                  },
                )
              else if (item.type == ContextMenuButtonType.selectAll)
                item,
          ];
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: editableTextState.contextMenuAnchors,
            buttonItems: items,
          );
        },
      ),
    );
  }
}
