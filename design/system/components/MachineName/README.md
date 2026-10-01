# MachineName

The exact string of an object on disk or in a download: a file in the library, a torrent, an NZB, a grabbed release. The title says *what* a thing is; the machine name says *which copy*.

Rendered from `lib/core/widgets/machine_name.dart` by `test/design_catalog/machine_name_catalog_test.dart`.

## Where it goes

Only in a row about a **copy**, under its title: a download (In flight, the Activity queues, a client's page), an acquisition (history, the Recently added rows), a refused release (the blocklist), a file to import, the file a session is playing. A row about a **title** never carries one: library grids, Discover, the calendar, Seerr requests, Wanted, the Recently added tiles. The requester never sees one. On a detail page the File section shows the file in full. **Today** only the File section of a movie's detail page uses it; the other surfaces take it up as they are redrawn.

## Anatomy

- Geist Mono, the `mono` role (`AppType.mono`, 13 / 18, 450, slashed zero), in the tertiary ink (`CupolaThemeColors.dimText`). The name is drawn as it came: no dots turned into spaces, no year cut off. A cleaned-up name looks like a title and is wrong with confidence.
- **In a row: one line, the ellipsis in the middle.** The front says what the copy is and the back, the group and the extension, says which one; an ellipsis at the end deletes exactly the half that answers *is this the right file?* The kept length is bisected with a `TextPainter` against the width the line is given, as many characters of the front as of the back, cached per width. The extension is always kept whole (`….mkv` is the floor, and below it the line clips); a separator never touches the ellipsis (`Next.…264` would read as a run of dots). No plate, no padding of its own: the host's row places it.
- **In full: the whole name, wrapping after its dots**, selectable, with a copy button (`Icons.copy_rounded` 18 in `on-surface-variant`, the theme's `IconButton`: 48 on a phone, 40 on a desktop, density pinned standard) centred beside it. A zero-width space after every dot and underscore is the break opportunity, because a dot between letters is not a break to the line breaker; it is drawn, never copied. The extension's dot gets none, so the extension stays on the segment before it. A `caption` is drawn ahead of the name in `body-small`, same ink: *Released as* `Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD`.

## Variants

- `MachineName.file(name)` and `MachineName.release(name)`: the row line.
- `MachineName.fileInFull(name, {caption})` and `MachineName.releaseInFull(name, {caption})`: the detail form.

File or release decides only the words of the copy action: *Copy file name*, *Copy release name*.

## Copying

The same everywhere, and always the exact string:

- a long press on a phone; the context menu (a secondary click) on a desktop, whose one item is the copy action; the copy button in full;
- in full, a selection copies what is selected, from the keyboard or from the selection toolbar, which keeps only Copy and Select all (Share, Look up and Search would hand the drawn text, break opportunities and all, to another app);
- the toast *Copied* confirms every copy the component makes. A copy from a text selection is a text field's and shows none.

On a desktop an elided name shows the whole one in a tooltip on hover. The tooltip never opens on touch, where the long press belongs to copying.

## The consumer provides

The name, exactly as the service returned it, and in full the `caption` when the name needs words ahead of it. A host row gives the line its width; the component measures it.

## Semantics

- **In a row the name is not part of the row's sentence.** Read aloud it is unlistenable and it repeats the title. The text is excluded and the component contributes one custom action, *Copy file name* or *Copy release name*, which merges into the row's node: the row still speaks one sentence and offers the copy. A host must therefore not wrap it in `ExcludeSemantics`, or the action goes too.
- **In full the name is read whole**, as its own node: the label is the caption (*Released as*) or *File name* / *Release name*, the value is the name, and the node carries the same custom action. The copy button is a sibling node, named by its tooltip.

## Do / don't

- Do put it under the title of a row about a copy, and nowhere else.
- Do pass the string as the service sent it.
- Don't trim, prettify or parse a machine name into a title. A name nobody recognises becomes the row's title in mono, with no machine name under it.
- Don't set figures in mono: a quality is a machine string, a size or a percentage is not.
- Don't give the row and the name two long presses: the inner one wins.
