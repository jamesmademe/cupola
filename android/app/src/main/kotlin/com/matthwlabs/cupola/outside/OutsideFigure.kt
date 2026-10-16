package com.matthwlabs.cupola.outside

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.text.TextPaint
import android.widget.TextView
import androidx.annotation.StyleRes
import kotlin.math.ceil

/**
 * The figure that leads a small Downloads (`3`, and `moving` beside it), in
 * the app's own face.
 *
 * A launcher cannot draw a `TextView` in a font of the app's (it inflates the
 * layout with a restricted context, which does not load one from the
 * resources), so this is the one part of a widget drawn here: into a bitmap,
 * with the face, axes, tracking and tabular figures of the role it names
 * (`OutsideText.FigureHero`, `FigureSmall`: the same `TextPaint` a `TextView`
 * made from the style would draw with in this process, where the font loads).
 *
 * The bitmap is a mask: it carries only the shape of the glyphs, and the
 * layout's `android:tint` gives it its colour from the resources, so the
 * launcher still resolves light and dark by itself, as for every other word.
 * The two parts share one height and one baseline, so that laid side by side
 * they sit on the same line, as the iOS widget's `firstTextBaseline` has them.
 */
internal object OutsideFigure {
    /** Whether this Android loads a font from the resources and sets its axes (8.0). */
    val available: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    /**
     * [text] in [style], on a line [height] tall whose baseline is where
     * [reference] puts it, so that two styles line up; null where no figure
     * can be drawn (below Android 8, or no room left in [bitmaps]).
     */
    fun mask(
        context: Context,
        @StyleRes style: Int,
        text: String,
        @StyleRes reference: Int,
        bitmaps: OutsideBitmaps,
    ): Bitmap? {
        if (!available || text.isEmpty()) return null
        val paint = paintOf(context, style)
        val anchor = paintOf(context, reference)
        // The reference's line: its height, and where its text sits in it.
        val height = ceil(lineOf(context, reference)).toInt()
        val metrics = anchor.fontMetrics
        val baseline = (height - (metrics.descent - metrics.ascent)) / 2f - metrics.ascent
        // A pixel of slack either side: a negative tracking and a glyph's own
        // overhang reach past the advance.
        val width = ceil(paint.measureText(text)).toInt() + 2
        if (width <= 0 || height <= 0 || !bitmaps.take(width, height)) return null
        val mask = Bitmap.createBitmap(width, height, Bitmap.Config.ALPHA_8)
        mask.density = Bitmap.DENSITY_NONE
        Canvas(mask).drawText(text, 1f, baseline, paint)
        return mask
    }

    /** The paint a `TextView` in [style] draws with, in this process. */
    private fun paintOf(context: Context, @StyleRes style: Int) =
        TextPaint(TextView(context, null, 0, style).paint).apply {
            color = Color.BLACK
            isAntiAlias = true
        }

    private fun lineOf(context: Context, @StyleRes style: Int): Float =
        TextView(context, null, 0, style).lineHeight.toFloat()
}
