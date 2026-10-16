package com.matthwlabs.cupola.outside

import android.appwidget.AppWidgetProvider
import androidx.annotation.StringRes
import com.matthwlabs.cupola.R

/**
 * The widgets Cupola has. [key] is the widget's key in the snapshot: the names of
 * `OutsideWidget` in `lib/features/outside/domain/outside_snapshot.dart`.
 * Which of them a person can add is not decided here: an operator has a
 * calendar and a queue, a requester has her requests, and a widget with
 * nothing for her says so (`outside_kind_absent`).
 */
enum class OutsideKind(
    val key: String,
    val provider: Class<out AppWidgetProvider>,
    @param:StringRes val title: Int,
) {
    COMING_UP("comingUp", OutsideComingUpWidget::class.java, R.string.outside_coming_up_name),
    DOWNLOADS("downloads", OutsideDownloadsWidget::class.java, R.string.outside_downloads_name),
    REQUESTS("requests", OutsideRequestsWidget::class.java, R.string.outside_requests_name),
}
