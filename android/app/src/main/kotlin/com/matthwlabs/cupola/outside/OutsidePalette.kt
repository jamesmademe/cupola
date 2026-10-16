package com.matthwlabs.cupola.outside

import android.view.View
import android.widget.RemoteViews
import androidx.annotation.IdRes
import com.matthwlabs.cupola.R
import kotlin.math.roundToInt

/**
 * A text or a bar that comes in one view per tone: its default (the ink, or the
 * dim ink, as the layout says) and each tone.
 *
 * **The colour is the view's and not the code's.** `RemoteViews` could set a
 * colour from code, but a colour set from code is the colour of the moment it
 * was set, and the launcher inflates a layout again whenever the system changes
 * room (light, dark), keeping the actions it was sent. Only a colour that the
 * layout names, `@color/outside_green`, is resolved again then, from
 * `values/` or `values-night/` (`outside_style.xml`, generated from the live
 * theme). So the layout has a view for each tone, in that tone's colour, and
 * drawing a tone is showing one and hiding the others.
 *
 * Red is not a tone here: a server out of reach is where the phone is, not a
 * fact about the server (`OutsideSnapshot`).
 */
internal class ToneSlot(
    @param:IdRes val default: Int,
    @param:IdRes val green: Int,
    @param:IdRes val amber: Int,
    @param:IdRes val blue: Int,
    @param:IdRes val neutral: Int,
) {
    val all = intArrayOf(default, green, amber, blue, neutral)

    /** The view for [tone]; null is the slot's default, the ink or the dim ink. */
    @IdRes
    fun idFor(tone: OutsideTone?): Int = when (tone) {
        null -> default
        OutsideTone.GREEN -> green
        OutsideTone.AMBER -> amber
        OutsideTone.BLUE -> blue
        OutsideTone.NEUTRAL -> neutral
    }
}

internal object OutsideSlots {
    val eyebrow = ToneSlot(
        R.id.eyebrow_default, R.id.eyebrow_green, R.id.eyebrow_amber,
        R.id.eyebrow_blue, R.id.eyebrow_neutral,
    )
    val words = ToneSlot(
        R.id.words_default, R.id.words_green, R.id.words_amber,
        R.id.words_blue, R.id.words_neutral,
    )
    val bar = ToneSlot(
        R.id.bar_default, R.id.bar_green, R.id.bar_amber,
        R.id.bar_blue, R.id.bar_neutral,
    )
}

internal fun RemoteViews.visible(@IdRes id: Int, visible: Boolean) =
    setViewVisibility(id, if (visible) View.VISIBLE else View.GONE)

/**
 * [text] in the view [id], and the view only while there is text: a view that
 * has nothing to say takes no room, so what is under it moves up, as it does
 * on iOS.
 */
internal fun RemoteViews.line(@IdRes id: Int, text: String?) {
    visible(id, text != null)
    if (text != null) setTextViewText(id, text)
}

/** [text] in [slot], in [tone]'s colour; with no text, no view of the slot is shown. */
internal fun RemoteViews.toned(slot: ToneSlot, tone: OutsideTone?, text: String?) {
    val chosen = if (text == null) 0 else slot.idFor(tone)
    for (id in slot.all) visible(id, id == chosen)
    if (text != null) setTextViewText(chosen, text)
}

/** A bar [progress] of the way (0 to 1), in [tone]'s colour; null draws none. */
internal fun RemoteViews.bar(slot: ToneSlot, tone: OutsideTone?, progress: Double?) {
    val chosen = if (progress == null) 0 else slot.idFor(tone)
    for (id in slot.all) visible(id, id == chosen)
    if (progress != null) {
        setProgressBar(chosen, BAR_MAX, (progress.coerceIn(0.0, 1.0) * BAR_MAX).roundToInt(), false)
    }
}

/** Fine enough that a bar's end never steps by more than a pixel. */
private const val BAR_MAX = 1000
