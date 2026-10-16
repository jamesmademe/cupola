package com.matthwlabs.cupola.outside

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import android.widget.RemoteViews
import com.matthwlabs.cupola.R

/** What a widget has to draw at one moment. */
internal sealed interface OutsideContent {
    /** The app has not written a file (or not one this code reads). */
    data object NoFile : OutsideContent

    /** A file, with nothing in it for this widget. */
    data object Absent : OutsideContent

    /** A frame of the snapshot. */
    data class Shown(val face: OutsideFace) : OutsideContent
}

/**
 * How a snapshot becomes a widget: the last frame whose time has come, drawn in
 * the size the launcher gives the widget.
 *
 * The snapshot's frames are already the drawings, each valid from an instant
 * (`OutsideFrame`), so nothing here makes up a word: it chooses a frame and
 * draws it, and `OutsideClock` sets the alarm that chooses again at the next
 * frame's time. The app asks for a redraw after each run (`outside_channel`).
 */
internal object OutsideRender {
    private const val TAG = "CupolaWidgets"

    /** The frame of [kind] whose time has come at [now]. */
    fun content(context: Context, kind: OutsideKind, now: Long): OutsideContent {
        val snapshot = OutsideShelf.read(context) ?: return OutsideContent.NoFile
        val frames = snapshot.widgets[kind.key].orEmpty()
        if (frames.isEmpty()) return OutsideContent.Absent
        // The last frame whose time has come; a file whose first frame is still
        // ahead (the clock was set back) draws that one rather than nothing.
        val current = frames.indexOfLast { it.from <= now }.coerceAtLeast(0)
        return OutsideContent.Shown(frames[current].face)
    }

    /** Draws every widget of every kind that is on a screen. */
    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (kind in OutsideKind.entries) {
            val ids = manager.getAppWidgetIds(ComponentName(context, kind.provider))
            if (ids.isNotEmpty()) update(context, manager, kind, ids)
        }
    }

    /**
     * Draws [ids], all widgets of [kind]. From Android 12 a widget carries its
     * layouts for the sizes it may take (`RemoteViews(Map)`) and the launcher
     * picks the one that fits as the person resizes it, with no call back to
     * this code; before it, the layout is chosen here from the size the launcher
     * reports (`OPTION_APPWIDGET_MIN_WIDTH`), and drawn again when it changes
     * (`onAppWidgetOptionsChanged`).
     *
     * An update that throws would take the app's process down with it (it runs
     * in a receiver), and a widget that is not drawn keeps the drawing it had:
     * the lesser harm.
     */
    fun update(context: Context, manager: AppWidgetManager, kind: OutsideKind, ids: IntArray) {
        try {
            val content = content(context, kind, System.currentTimeMillis())
            val bitmaps = OutsideBitmaps(context)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val sized = OutsideSizes.keys.associateWith { draw(context, kind, content, it, bitmaps) }
                manager.updateAppWidget(ids, RemoteViews(sized))
            } else {
                for (id in ids) {
                    val size = OutsideSizes.of(manager.getAppWidgetOptions(id))
                    manager.updateAppWidget(id, draw(context, kind, content, size, bitmaps))
                }
            }
        } catch (e: RuntimeException) {
            Log.w(TAG, "A widget was not drawn", e)
        }
    }

    private fun draw(
        context: Context,
        kind: OutsideKind,
        content: OutsideContent,
        size: SizeF,
        bitmaps: OutsideBitmaps,
    ): RemoteViews {
        val plate = Plate(context, kind, size.width, size.height, bitmaps)
        val views = when (content) {
            OutsideContent.NoFile -> emptyView(plate, kind, R.string.outside_no_file)
            OutsideContent.Absent -> emptyView(plate, kind, R.string.outside_kind_absent)
            is OutsideContent.Shown -> when (kind) {
                OutsideKind.COMING_UP -> OutsideComingUp.draw(plate, content.face)
                OutsideKind.DOWNLOADS -> OutsideDownloads.draw(plate, content.face)
                OutsideKind.REQUESTS -> OutsideRequests.draw(plate, content.face)
            }
        }
        // Where a tap on the widget, away from its rows, opens; with no place
        // named it opens the app, as an empty widget does.
        plate.tap(
            views,
            android.R.id.background,
            (content as? OutsideContent.Shown)?.face?.route,
            0,
        )
        return views
    }
}

/**
 * The sizes a widget is drawn in, in dp. A widget of Android 12 or later carries
 * a layout for each of these and the launcher shows the one that is the largest
 * to fit the room the widget has, so they are the steps at which what a widget
 * draws can change. Launchers do not agree on a cell (`70n - 30` dp is the
 * guideline: two cells are 110dp and four are 250dp, and the emulator's launcher
 * gives 179dp for two and 373dp for four), so the steps are ranges a phone
 * gives and not the guideline's cells.
 *
 * A small layout is a plate that crops to its room: one width, two heights
 * (what a short plate keeps is a question of height). A medium one is a list,
 * where the width is where a title is cut and the height is how many rows fit
 * and how tall the poster is: seven widths, a step of [WIDTH_STEP] apart from
 * four cells (250dp) up, and two heights. Sixteen in all, the most `RemoteViews`
 * takes; the launcher shows a small one wherever no medium one fits.
 */
internal object OutsideSizes {
    const val WIDTH_STEP = 25f

    private val small = listOf(110f, 170f).map { SizeF(110f, it) }
    private val mediumWidths = (0..6).map { 250f + it * WIDTH_STEP }
    private val mediumHeights = listOf(110f, 190f)

    /** What a widget of Android 12 or later carries: the layout for each size. */
    val keys: List<SizeF> =
        small + mediumWidths.flatMap { width -> mediumHeights.map { SizeF(width, it) } }

    /**
     * The size the launcher reports for a widget before Android 12: its least
     * width and height, which are what it is guaranteed (the launcher may give
     * it more), or the smallest the widget goes where it reports none.
     */
    fun of(options: Bundle): SizeF = SizeF(
        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0).toFloat()
            .coerceAtLeast(small.first().width),
        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0).toFloat()
            .coerceAtLeast(small.first().height),
    )
}
