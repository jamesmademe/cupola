package com.matthwlabs.cupola.outside

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.matthwlabs.cupola.MainActivity

/**
 * What a tap on a widget opens: `cupola://open?to=/activity`.
 *
 * The snapshot names each place as a location of the app's router
 * (`OutsideFace.route`, `OutsideItem.route`); the widget, which runs no Dart,
 * wraps it in this link, and the app takes it back off (`OutsideLink.routeOf` in
 * `lib/features/outside/domain/outside_link.dart`). It is the same link as
 * iOS's (`OutsideLink.swift`), and it is built here and nowhere else.
 *
 * The intent is **explicit**, to [MainActivity]: an explicit intent needs no
 * filter, so the Manifest's `cupola://` filter stays `invite` only and nothing
 * else on the phone can open a widget's links.
 */
object OutsideLink {
    private const val UNRESERVED =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

    /**
     * Everything but the unreserved characters is escaped, `/`, `?`, `&`, `=`
     * and `%` included: the route is one query value, and its own query must
     * not read as the link's. Dart decodes it whole (`Uri.queryParameters`).
     */
    fun encode(route: String): String = buildString {
        for (byte in route.toByteArray(Charsets.UTF_8)) {
            val char = (byte.toInt() and 0xFF).toChar()
            if (char in UNRESERVED) {
                append(char)
            } else {
                append('%').append("%02X".format(byte.toInt() and 0xFF))
            }
        }
    }

    /** The link that opens [route], or the app's Home where there is none to name. */
    fun uri(route: String?): Uri =
        Uri.parse(if (route.isNullOrEmpty()) "cupola://open" else "cupola://open?to=${encode(route)}")

    /**
     * The tap that opens [route]. [requestCode] tells one tap of one widget
     * from another: a row has its own, so no row's tap replaces a neighbour's.
     */
    fun tap(context: Context, route: String?, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, uri(route))
            .setClass(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
