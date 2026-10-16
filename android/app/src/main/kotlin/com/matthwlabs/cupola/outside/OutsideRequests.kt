package com.matthwlabs.cupola.outside

import android.widget.RemoteViews
import com.matthwlabs.cupola.R

/**
 * Your requests: what she asked for, and when it is ready. Only hers, in the
 * words the Home gives them, and no service's name.
 *
 * Small leads with what is ready to watch over its artwork, as Coming up does;
 * with nothing ready it names itself and gives its first request. Medium is her
 * requests, a tiny poster before each. The same drawing as
 * `OutsideRequests.swift`.
 */
internal object OutsideRequests {
    private const val ROWS = 3

    fun draw(p: Plate, face: OutsideFace): RemoteViews =
        if (p.isMedium) medium(p, face) else small(p, face)

    private fun small(p: Plate, face: OutsideFace): RemoteViews {
        val lead = face.lead
        val first = face.items.firstOrNull()
        return when {
            // Ready to watch is the eyebrow's tone (green); the words are the
            // count of what is still on its way, which has none.
            lead != null -> leadPlate(p, face, lead, eyebrowTone = lead.tone, wordsTone = null)
            first != null -> statSmall(p, face, null, null, null, first)
            else -> calmSmall(p, face)
        }
    }

    /**
     * Medium's rows: the face's own, or its lead as a row when the face has no
     * others (the Home lists what is ready among its rows; a face that does not
     * must not draw nothing while it has a lead).
     */
    private fun rowsOf(face: OutsideFace): List<OutsideItem> {
        if (face.items.isNotEmpty()) return face.items.take(ROWS)
        val lead = face.lead ?: return emptyList()
        return listOf(
            OutsideItem(
                title = lead.title,
                words = lead.eyebrow,
                tone = lead.tone,
                poster = lead.poster,
                route = lead.route,
            ),
        )
    }

    private fun medium(p: Plate, face: OutsideFace): RemoteViews {
        val m = p.measure
        val gap = p.dp(R.dimen.outside_space_s)
        val rowHeight = maxOf(p.dp(R.dimen.outside_tiny_poster_height), m.height(m.line))
        val rows = rowsOf(face)
            .filter { fits(p, it) }
            .take(rowsThatFit(p.innerHeight - listHead(p), rowHeight, gap, ROWS))
        return mediumList(
            p, face.title, face, tight = true,
            rows = rows.mapIndexed { index, item -> row(p, item, index + 1) },
        )
    }

    private fun fits(p: Plate, item: OutsideItem): Boolean {
        val m = p.measure
        val gap = p.dp(R.dimen.outside_space_sm)
        val poster = p.dp(R.dimen.outside_tiny_poster_width) + p.dp(R.dimen.outside_space_row)
        val words = item.words?.let { m.width(m.line, breakable(it)) + gap } ?: 0f
        return m.titleFits(m.line, item.title, p.innerWidth - poster - words)
    }

    private fun row(p: Plate, item: OutsideItem, slot: Int): RemoteViews {
        val v = p.views(R.layout.outside_row_request)
        // The poster's place is kept where there is no picture: the layout's
        // own track, so the titles line up.
        item.poster?.let { name ->
            OutsideShelf.picture(
                p.context, name,
                p.px(p.dp(R.dimen.outside_tiny_poster_width)),
                p.px(p.dp(R.dimen.outside_tiny_poster_height)),
                p.px(p.dp(R.dimen.outside_tiny_poster_radius)).toFloat(),
                p.bitmaps,
            )?.let { v.setImageViewBitmap(R.id.poster, it) }
        }
        v.setTextViewText(R.id.title, item.title)
        v.toned(OutsideSlots.words, item.tone, item.words?.let(::breakable))
        v.setContentDescription(R.id.row, spoken(item.title, item.words))
        if (item.route != null) p.tap(v, R.id.row, item.route, slot)
        return v
    }
}
