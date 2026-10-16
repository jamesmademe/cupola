package com.matthwlabs.cupola.outside

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * Turns a widget's frame when its time comes, without the app: midnight, where
 * `Today` becomes `Yesterday`, and the time a thing airs.
 *
 * One alarm, at the earliest later frame of the widgets that are on a screen,
 * **inexact and not waking the phone** (`AlarmManager.set(RTC, …)`): the frame
 * turns when the phone next wakes at or after its time, which is soon enough for
 * a line of words, and it needs no permission. An exact alarm would need
 * `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM`, which the Play Store restricts
 * to apps whose function is a clock or a calendar: a widget's `Today` is not
 * worth the declaration. After a restart the launcher asks each widget for
 * its drawing again and `onUpdate` sets the alarm once more, so nothing needs
 * `RECEIVE_BOOT_COMPLETED` either.
 */
internal object OutsideClock {
    /** Sets the alarm for the widgets that are on a screen now, or clears it when there are none. */
    fun arm(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, OutsideTick::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val next = nextFrame(context, System.currentTimeMillis())
        if (next == null) alarms.cancel(pending) else alarms.set(AlarmManager.RTC, next, pending)
    }

    /** The earliest frame after [now] of any widget that is on a screen, or null. */
    private fun nextFrame(context: Context, now: Long): Long? {
        val snapshot = OutsideShelf.read(context) ?: return null
        val manager = AppWidgetManager.getInstance(context)
        return OutsideKind.entries
            .filter { manager.getAppWidgetIds(ComponentName(context, it.provider)).isNotEmpty() }
            .flatMap { snapshot.widgets[it.key].orEmpty() }
            .map { it.from }
            .filter { it > now }
            .minOrNull()
    }
}

/** The alarm's receiver (`OutsideClock`): draws the widgets again, and sets the next alarm. */
class OutsideTick : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        OutsideRender.updateAll(context)
        OutsideClock.arm(context)
    }
}
