package com.matthwlabs.cupola.outside

import android.widget.RemoteViews
import com.matthwlabs.cupola.R

/**
 * Downloads: what is moving, and what is stuck.
 *
 * Small is the one figure, what leads under it, and where it stands. Medium is
 * the rows, each with its bar. The lock screen's rectangle has no twin here.
 * The same drawing as `OutsideDownloads.swift`.
 *
 * A calm face (`calm` is set: nothing is downloading) says it once, in its calm
 * line, and never draws its subtitle, which would say it again.
 */
internal object OutsideDownloads {
    private const val ROWS = 3

    fun draw(p: Plate, face: OutsideFace): RemoteViews =
        if (p.isMedium) medium(p, face) else small(p, face)

    /** The module's line, unless the face is calm. */
    private fun subtitle(face: OutsideFace): String? = if (face.calm == null) face.subtitle else null

    private fun small(p: Plate, face: OutsideFace): RemoteViews {
        val subtitle = subtitle(face)
        // What leads is the stuck one, which needs a person; failing that, the
        // first that moves. With neither, the face's own word that it is calm.
        val item = face.lead ?: face.items.firstOrNull()
        return statSmall(
            p, face,
            figure = face.figure,
            figureWords = face.figureWords,
            subtitle = if (face.figure == null) subtitle?.let(::breakable) else null,
            item = item,
        )
    }

    /**
     * The stuck one first, then the rest. The face lists the stuck ones among
     * its items as well (the Home's rows do), so the lead is not drawn twice.
     */
    private fun medium(p: Plate, face: OutsideFace): RemoteViews {
        val m = p.measure
        val candidates = (listOfNotNull(face.lead) + face.items.filter { it != face.lead }).take(ROWS)
        val gap = p.dp(R.dimen.outside_space_row)
        // A row is its line, a gap and its bar.
        val rowHeight = m.height(m.line) + p.dp(R.dimen.outside_space_xs) + p.dp(R.dimen.outside_bar_height)
        val rows = candidates
            .filter { fits(p, it) }
            .take(rowsThatFit(p.innerHeight - listHead(p), rowHeight, gap, ROWS))
        val leading = subtitle(face) ?: face.title
        return mediumList(
            p, leading, face, tight = false,
            rows = rows.mapIndexed { index, item -> row(p, item, index + 1) },
        )
    }

    private fun fits(p: Plate, item: OutsideItem): Boolean {
        val m = p.measure
        val words = item.words?.let { m.width(m.data, breakable(it)) + p.dp(R.dimen.outside_space_sm) } ?: 0f
        return m.titleFits(m.line, item.title, p.innerWidth - words)
    }

    private fun row(p: Plate, item: OutsideItem, slot: Int): RemoteViews {
        val v = p.views(R.layout.outside_row_download)
        v.setTextViewText(R.id.title, item.title)
        v.toned(OutsideSlots.words, item.tone, item.words?.let(::breakable))
        v.bar(OutsideSlots.bar, item.tone, item.progress)
        v.setContentDescription(R.id.row, spoken(item.title, item.words))
        if (item.route != null) p.tap(v, R.id.row, item.route, slot)
        return v
    }
}

/**
 * A small widget on its ground that leads with a figure or a line and under it
 * one thing with its bar: Downloads, and Your requests when nothing is ready.
 * With no thing, its calm line and, where the drawing is old, its age.
 *
 * Every optional view is shown or hidden here, whichever way it goes: a launcher
 * that is sent a drawing of the same layout again applies it to the view it
 * already has, where a view left alone keeps what an earlier drawing did to it.
 */
internal fun statSmall(
    p: Plate,
    face: OutsideFace,
    figure: String?,
    figureWords: String?,
    subtitle: String?,
    item: OutsideItem?,
): RemoteViews {
    val v = p.views(R.layout.outside_stat_small)
    v.setTextViewText(R.id.name, face.title)
    v.visible(R.id.figure_row, figure != null)
    if (figure != null) {
        v.setContentDescription(R.id.figure_row, spoken(figure, figureWords))
        // The app's own face, as a bitmap (OutsideFigure), the words beside it
        // on the same baseline; before Android 8, or with no room for a
        // bitmap, the system face.
        val hero = OutsideFigure.mask(
            p.context, R.style.OutsideText_FigureHero, figure, R.style.OutsideText_FigureHero, p.bitmaps,
        )
        val words = if (hero == null || figureWords == null) {
            null
        } else {
            OutsideFigure.mask(
                p.context, R.style.OutsideText_FigureSmall, figureWords, R.style.OutsideText_FigureHero, p.bitmaps,
            )
        }
        if (hero != null) v.setImageViewBitmap(R.id.figure_mask, hero)
        if (words != null) v.setImageViewBitmap(R.id.figure_words_mask, words)
        v.visible(R.id.figure_mask, hero != null)
        v.visible(R.id.figure_words_mask, words != null)
        v.visible(R.id.figure, hero == null)
        if (hero == null) v.setTextViewText(R.id.figure, figure)
        v.line(R.id.figure_words, if (hero == null) figureWords else null)
    }
    v.line(R.id.subtitle, subtitle)
    v.visible(R.id.item, item != null)
    if (item != null) {
        v.setTextViewText(R.id.item_title, item.title)
        // A widget that is short keeps what says the most: the bar is the
        // first to go (the words say the same, in their tone), then the last
        // line, rather than a line cut in half at the foot.
        val m = p.measure
        val head = 2 * p.slab + m.height(m.label) + p.dp(R.dimen.outside_space_sm) +
            (if (figure != null) m.height(m.figure) else if (subtitle != null) m.height(m.line) else 0f) +
            p.dp(R.dimen.outside_space_row) + m.height(m.title)
        val last = p.dp(R.dimen.outside_space_xs) + m.height(m.line)
        val bar = p.dp(R.dimen.outside_space_xs) + p.dp(R.dimen.outside_bar_height)
        val showsBar = head + bar + last <= p.heightDp
        val showsLast = head + last <= p.heightDp
        v.bar(OutsideSlots.bar, item.tone, if (showsBar) item.progress else null)
        // The age takes the place of the last line where the drawing is old
        // enough to say so.
        v.line(R.id.age, if (face.aged && showsLast) face.age else null)
        v.toned(
            OutsideSlots.words, item.tone,
            if (face.aged || !showsLast) null else item.words?.let(::breakable),
        )
    }
    v.line(R.id.calm, if (item == null) face.calm else null)
    v.line(R.id.calm_age, if (item == null && face.aged) face.age else null)
    return v
}
