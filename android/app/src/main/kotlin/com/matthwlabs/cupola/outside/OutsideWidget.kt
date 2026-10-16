package com.matthwlabs.cupola.outside

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Build
import android.os.Bundle

/**
 * One provider for the three widgets: they differ in what they draw
 * (`OutsideComingUp`, `OutsideDownloads`, `OutsideRequests`) and in which
 * snapshot key they read, not in how a snapshot becomes a widget.
 *
 * Nothing is drawn on a period of the system's (`updatePeriodMillis` is 0): the
 * app's own run asks for a redraw (`outside_channel`), and the alarm of
 * `OutsideClock` turns the frame at its time.
 */
abstract class OutsideWidgetProvider(private val kind: OutsideKind) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        OutsideRender.update(context, manager, kind, ids)
        OutsideClock.arm(context)
    }

    /**
     * Before Android 12 the layout is chosen from the size, here; from it the
     * launcher chooses among the layouts the widget carries.
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            OutsideRender.update(context, manager, kind, intArrayOf(id))
        }
    }

    // The widgets that are left decide the alarm.
    override fun onDeleted(context: Context, ids: IntArray) = OutsideClock.arm(context)

    override fun onDisabled(context: Context) = OutsideClock.arm(context)
}

class OutsideComingUpWidget : OutsideWidgetProvider(OutsideKind.COMING_UP)

class OutsideDownloadsWidget : OutsideWidgetProvider(OutsideKind.DOWNLOADS)

class OutsideRequestsWidget : OutsideWidgetProvider(OutsideKind.REQUESTS)
