package com.matthwlabs.cupola.outside

import android.widget.RemoteViews
import com.matthwlabs.cupola.R

/**
 * Coming up: what airs and comes out next.
 *
 * Small leads with the next title over its own artwork. Medium puts the lead's
 * poster at the left, its words beside it, and the next things under them. The
 * face says which is the lead and which are the rest. The same drawing as
 * `OutsideComingUp.swift`.
 */
internal object OutsideComingUp {
    /** Rows that fit a medium widget beside its lead: the face has a lead and these. */
    private const val ROWS = 2

    fun draw(p: Plate, face: OutsideFace): RemoteViews {
        val lead = face.lead ?: return calm(p, face)
        return if (p.isMedium) medium(p, face, lead) else small(p, face, lead)
    }

    private fun calm(p: Plate, face: OutsideFace): RemoteViews =
        if (p.isMedium) mediumList(p, face.title, face, tight = false, rows = emptyList())
        else calmSmall(p, face)

    private fun small(p: Plate, face: OutsideFace, lead: OutsideItem): RemoteViews =
        leadPlate(p, face, lead, eyebrowTone = null, wordsTone = lead.tone)

    private fun medium(p: Plate, face: OutsideFace, lead: OutsideItem): RemoteViews {
        val v = p.views(R.layout.outside_medium_coming)
        val posterHeight = p.innerHeight
        val posterWidth = posterHeight * 2f / 3f
        val poster = lead.poster?.let {
            OutsideShelf.picture(
                p.context, it, p.px(posterWidth), p.px(posterHeight),
                p.px(p.dp(R.dimen.outside_poster_radius)).toFloat(), p.bitmaps,
            )
        }
        if (poster != null) v.setImageViewBitmap(R.id.poster, poster)
        v.visible(R.id.poster, poster != null)
        // The eyebrow says when, and the age says how fresh: the one line the
        // other mediums give to their header.
        v.setTextViewText(R.id.header_leading, breakable(lead.eyebrow ?: ""))
        v.setTextViewText(R.id.header_trailing, breakable(face.age))
        v.setTextViewText(R.id.title, lead.title)
        v.toned(OutsideSlots.words, lead.tone, lead.words?.let(::breakable))

        val column = p.innerWidth - if (poster != null) posterWidth + p.slab else 0f
        val m = p.measure
        // The lead's own height: the header, the title in one line or two, and
        // its words. What is left under it is the rows', after a gap.
        val titleLines = if (m.width(m.title, lead.title) > column) 2 else 1
        val leadHeight = m.height(m.label) + p.dp(R.dimen.outside_space_xxs) +
            titleLines * m.height(m.title) + if (lead.words != null) m.height(m.line) else 0f
        val gap = p.dp(R.dimen.outside_space_s)
        val room = p.innerHeight - leadHeight - gap
        val fitting = face.items.take(ROWS)
            .filter { fits(p, it, column) }
            .take(rowsThatFit(room, m.height(m.line), gap, ROWS))
        // See `mediumList`: a drawing applied again must not add to the rows it has.
        v.removeAllViews(R.id.rows_tight)
        fitting.forEachIndexed { index, item -> v.addView(R.id.rows_tight, row(p, item, index + 1)) }
        return v
    }

    /** Whether [item]'s title keeps its start in the room its day and its words leave. */
    private fun fits(p: Plate, item: OutsideItem, column: Float): Boolean {
        val m = p.measure
        val gap = p.dp(R.dimen.outside_space_sm)
        val day = if (item.eyebrow != null) p.dp(R.dimen.outside_day_column) + gap else 0f
        val words = item.words?.let { m.width(m.data, breakable(it)) + gap } ?: 0f
        return m.titleFits(m.line, item.title, column - day - words)
    }

    /** `Tomorrow  Sprite Fright  S1 E3`: one node for a screen reader. */
    private fun row(p: Plate, item: OutsideItem, slot: Int): RemoteViews {
        val v = p.views(R.layout.outside_row_coming)
        v.line(R.id.day, item.eyebrow)
        v.setTextViewText(R.id.title, item.title)
        v.toned(OutsideSlots.words, item.tone, item.words?.let(::breakable))
        v.setContentDescription(R.id.row, spoken(item.eyebrow, item.title, item.words))
        if (item.route != null) p.tap(v, R.id.row, item.route, slot)
        return v
    }
}
