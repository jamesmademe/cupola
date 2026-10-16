package com.matthwlabs.cupola.outside

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Typeface
import android.os.Build
import android.widget.RemoteViews
import android.widget.TextView
import androidx.annotation.DimenRes
import androidx.annotation.IdRes
import androidx.annotation.LayoutRes
import androidx.annotation.StringRes
import androidx.annotation.StyleRes
import com.matthwlabs.cupola.R
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * What a widget is drawn into: the size the launcher gives it (in dp, as
 * Android's launchers measure) and what a drawing needs to know about it.
 *
 * A widget does not scroll, and `RemoteViews` cannot measure: it cannot say
 * that a row does not fit, only draw it and be cut. So the room is reasoned
 * here, in dp, from the same type roles the layouts use (`OutsideMeasure`), and
 * a row that would not fit is not drawn, rather than drawn cut.
 */
internal class Plate(
    val context: Context,
    val kind: OutsideKind,
    val widthDp: Float,
    val heightDp: Float,
    val bitmaps: OutsideBitmaps,
) {
    val density: Float = context.resources.displayMetrics.density
    val measure = OutsideMeasure(context)

    /** From four cells wide, a widget is drawn as a list, not as a plate. */
    val isMedium: Boolean get() = widthDp >= MEDIUM_FROM_DP

    val slab: Float = dp(R.dimen.outside_space_slab_y)

    /**
     * What a row can use of the width. The launcher gives a widget the layout
     * of the largest size that fits it, so the room is the size's width and up
     * to a step more: half a step is the best guess, and a title that is then a
     * little short of room is still cut where it keeps its start (`titleFits`).
     */
    val innerWidth: Float
        get() = widthDp - 2 * slab + if (isMedium) OutsideSizes.WIDTH_STEP / 2 else 0f
    val innerHeight: Float get() = heightDp - 2 * slab

    /** A dimension of the resources, in dp (an sp one at the person's text scale). */
    fun dp(@DimenRes id: Int): Float =
        context.resources.getDimension(id) / density

    fun px(dp: Float): Int = (dp * density).roundToInt()

    fun views(@LayoutRes layout: Int) = RemoteViews(context.packageName, layout)

    /**
     * Where a tap on [viewId] of [views] opens: [route], through one link
     * built in one place (`OutsideLink`). The request code is the tap's own:
     * [slot] is 0 for the widget and 1 and up for its rows.
     */
    fun tap(views: RemoteViews, @IdRes viewId: Int, route: String?, slot: Int) {
        views.setOnClickPendingIntent(viewId, OutsideLink.tap(context, route, kind.ordinal * 100 + slot))
    }

    /**
     * The artwork a small widget is drawn over: the backdrop first, else the
     * poster.
     *
     * From Android 12 the layout's root clips its children to the widget's
     * corners (`clipToOutline` is an attribute only from there), so one square
     * picture serves every size and the launcher crops it. Before it nothing
     * clips, so the corners are the picture's own, and the picture is exactly
     * the widget's size, so that they are drawn at the radius they have.
     */
    fun artwork(lead: OutsideItem): Bitmap? {
        val clipped = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        val width = if (clipped) px(ART_DP) else px(widthDp)
        val height = if (clipped) px(ART_DP) else px(heightDp)
        val radius = if (clipped) 0f else px(dp(R.dimen.outside_widget_radius)).toFloat()
        for (name in listOfNotNull(lead.backdrop, lead.poster)) {
            OutsideShelf.picture(context, name, width, height, radius, bitmaps)?.let { return it }
        }
        return null
    }

    companion object {
        /**
         * Where a plate gives way to a list. The launcher's four cells are 250dp
         * or more and its two are about 180dp at most, so a widget a little over
         * three cells wide is the plate with room to spare (`OutsideSizes`).
         */
        const val MEDIUM_FROM_DP = 220f

        /**
         * The side of the square artwork a small widget is drawn over, however
         * the launcher stretches it (it is cropped to fit, never squashed):
         * big enough for a tall three-cell widget, small enough that it is a
         * megabyte or so of the bitmaps a widget may carry.
         */
        const val ART_DP = 220f
    }
}

/**
 * Text as the launcher draws it, measured.
 *
 * A launcher inflates a widget's layout with a restricted context, which does
 * not load a font from the app's resources: the style's `fontFamily` is the
 * system face there (see `outside_style.xml`), and only the weight, size,
 * tracking and line reach it. So the measuring view is made from the same style
 * and then given the system face with the same variation, which is the face the
 * launcher draws, and not the face the style names, which this process can load
 * and the launcher cannot.
 */
internal class OutsideMeasure(private val context: Context) {
    private val density = context.resources.displayMetrics.density

    private fun view(@StyleRes style: Int): TextView {
        val view = TextView(context, null, 0, style)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val variation = view.fontVariationSettings
            view.typeface = Typeface.DEFAULT
            view.fontVariationSettings = variation
        } else {
            view.typeface = Typeface.DEFAULT
        }
        return view
    }

    val label by lazy { view(R.style.OutsideText_Label) }
    val title by lazy { view(R.style.OutsideText_Title) }
    val line by lazy { view(R.style.OutsideText_Line) }
    val data by lazy { view(R.style.OutsideText_Data) }
    val figure by lazy { view(R.style.OutsideText_FigureHero) }

    /** [text] on one line in [role], in dp. */
    fun width(role: TextView, text: String): Float = role.paint.measureText(text) / density

    /** A line of [role], in dp, at the person's text scale. */
    fun height(role: TextView): Float = role.lineHeight / density

    /**
     * Whether a title can be drawn in [room] dp without being cut to nothing.
     * A title that fits whole is drawn; a longer one is cut at the end, and
     * only if what is left is still the start of a name and not a letter or two
     * (`S…` was the worst defect the iOS pass found). Where even that does not
     * fit, the row is not drawn.
     */
    fun titleFits(role: TextView, title: String, room: Float): Boolean {
        if (width(role, title) <= room) return true
        if (title.length <= MIN_TITLE_CHARS) return false
        return width(role, title.take(MIN_TITLE_CHARS)) + width(role, ELLIPSIS) <= room
    }

    private companion object {
        /** The start of a title that must stay when it is cut. */
        const val MIN_TITLE_CHARS = 10
        const val ELLIPSIS = "…"
    }
}

/** How many rows of [row] dp, [gap] dp apart, fit in [available] dp, at most [limit]. */
internal fun rowsThatFit(available: Float, row: Float, gap: Float, limit: Int): Int =
    min(limit, max(0, floor((available + gap) / (row + gap)).toInt()))

/**
 * [text] with its spaces made non-breaking inside each part between ` · `
 * separators, so that a line breaks only at a separator and never inside a part
 * (`2.4 MB/s`, `S1 E4`). The separators keep their ordinary spaces.
 */
internal fun breakable(text: String): String =
    text.split(" · ").joinToString(" · ") { it.replace(' ', ' ') }

/** A row's words in reading order, for a screen reader: one node, its parts silenced. */
internal fun spoken(vararg parts: String?): String = parts.filterNotNull().joinToString(", ")

/** `Nothing is downloading`, or whatever the face says, over its name: a calm small widget. */
internal fun calmSmall(p: Plate, face: OutsideFace): RemoteViews {
    val v = p.views(R.layout.outside_calm_small)
    v.setTextViewText(R.id.name, face.title)
    v.line(R.id.calm, face.calm)
    v.line(R.id.age, if (face.aged) face.age else null)
    return v
}

/**
 * A medium list's frame: its header, with what it is on the left and how old it
 * is on the right, and what it lists directly under it, top-aligned. [rows]
 * adds them to the container it is given; with none, [face]'s calm line says so.
 *
 * The leading text is cut before the age is: the age is never truncated.
 */
internal fun mediumList(
    p: Plate,
    leading: String,
    face: OutsideFace,
    tight: Boolean,
    rows: List<RemoteViews>,
): RemoteViews {
    val v = p.views(R.layout.outside_medium_list)
    v.setTextViewText(R.id.header_leading, breakable(leading))
    v.setTextViewText(R.id.header_trailing, breakable(face.age))
    val container = if (tight) R.id.rows_tight else R.id.rows
    v.visible(R.id.rows, rows.isNotEmpty() && !tight)
    v.visible(R.id.rows_tight, rows.isNotEmpty() && tight)
    // `addView` adds to what the view already has, and a launcher that is
    // sent a drawing of the same layout again applies it to the view it
    // already inflated: without this the rows pile up, one set per update.
    v.removeAllViews(R.id.rows)
    v.removeAllViews(R.id.rows_tight)
    for (row in rows) v.addView(container, row)
    // Said only when there is nothing else to say.
    v.line(R.id.calm, if (rows.isEmpty()) face.calm else null)
    return v
}

/** The height of a medium list's header and the gap under it, in dp. */
internal fun listHead(p: Plate): Float = p.measure.height(p.measure.label) + p.dp(R.dimen.outside_space_row)

/** A widget with nothing to draw: its name and one line. */
internal fun emptyView(p: Plate, kind: OutsideKind, @StringRes line: Int): RemoteViews {
    val v = p.views(R.layout.outside_empty)
    v.setTextViewText(R.id.name, p.context.getString(kind.title))
    v.setTextViewText(R.id.line, p.context.getString(line))
    return v
}

/**
 * A small widget that leads with one thing: an eyebrow, a title (two lines
 * before it is cut, since the picture behind it has room), and what it says,
 * over the lead's own artwork or, with none, on the ground with the widget's
 * name at the top, as the other small widgets have it.
 *
 * Over artwork the words are the artwork's (`outside_on_art`, the same in both
 * rooms), and a tone is the dark room's, since the scrim is its ground; on the
 * ground they are the room's. Where the drawing is old enough to say so, the
 * age takes the place of the last line.
 *
 * [eyebrowTone] and [wordsTone] say which part of the lead the tone belongs to:
 * Coming up's is its words' state, Your requests' is the eyebrow's (`Ready to
 * watch`, green).
 */
internal fun leadPlate(
    p: Plate,
    face: OutsideFace,
    lead: OutsideItem,
    eyebrowTone: OutsideTone?,
    wordsTone: OutsideTone?,
): RemoteViews {
    val art = p.artwork(lead)
    val v = p.views(if (art != null) R.layout.outside_lead_art else R.layout.outside_lead_ground)
    if (art != null) v.setImageViewBitmap(R.id.art, art) else v.setTextViewText(R.id.name, face.title)
    v.toned(OutsideSlots.eyebrow, eyebrowTone, lead.eyebrow?.let(::breakable))
    v.setTextViewText(R.id.title, lead.title)
    // Words over artwork have no tone (they are `on_art_dim`), and neither has
    // an age.
    val last = if (face.aged) face.age else lead.words?.let(::breakable)
    v.toned(OutsideSlots.words, if (art != null || face.aged) null else wordsTone, last)
    return v
}
