package com.matthwlabs.cupola.outside.channel

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The channel `cupola/outside` (`lib/features/outside/data/outside_native.dart`)
 * as Android answers it. iOS answers the same three methods from
 * `OutsideChannel` in `ios/Runner/AppDelegate.swift`.
 *
 * It is a plugin and not a channel set up in `MainActivity` because the
 * background read runs in a `FlutterEngine` of WorkManager's own
 * (`workmanager_android`'s `BackgroundWorker`), which registers only the
 * plugins of the generated registrant. A channel on the activity's engine
 * does not exist there, and the `reload` that ends a background run, which is
 * the one that matters, would be lost.
 *
 * The plugin knows no class of the app: the widgets are found through the
 * system's list of providers, by package, so a fourth widget needs nothing here.
 */
class OutsideChannelPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = context
        if (context == null) {
            result.error("detached", "The plugin is not attached to an engine.", null)
            return
        }
        try {
            when (call.method) {
                "sharedFolder" -> result.success(sharedFolder(context))
                "reload" -> {
                    reload(context)
                    result.success(null)
                }
                "installed" -> result.success(placed(context).isNotEmpty())
                else -> result.notImplemented()
            }
        } catch (e: RuntimeException) {
            // The next run asks again; Dart treats any failure here as such.
            result.error("outside", e.message, null)
        }
    }

    /**
     * Where the app writes what the widgets draw and where they read it.
     *
     * Android has no App Group: the widgets run in the app's own process and
     * read its own folder. This is `filesDir/outside`, which is also where
     * `getApplicationSupportDirectory()` points on Android, so the path Dart
     * falls back to where this channel is absent is the same folder. The
     * widgets' Kotlin (`OutsideShelf`) names it once more; keep them in step.
     */
    private fun sharedFolder(context: Context): String =
        context.filesDir.resolve(FOLDER).absolutePath

    /**
     * The package's widget providers that have at least one widget on a
     * screen, each with the ids of its widgets.
     */
    private fun placed(context: Context): List<Pair<ComponentName, IntArray>> {
        val manager = AppWidgetManager.getInstance(context)
        return manager.installedProviders
            .filter { it.provider.packageName == context.packageName }
            .map { it.provider to manager.getAppWidgetIds(it.provider) }
            .filter { (_, ids) -> ids.isNotEmpty() }
    }

    /**
     * Asks each provider that has a widget to draw it again. The order is the
     * system's own (`ACTION_APPWIDGET_UPDATE`, which every
     * `AppWidgetProvider` answers in `onUpdate`), sent to the provider by name
     * and so received only by it.
     */
    private fun reload(context: Context) {
        for ((provider, ids) in placed(context)) {
            val update = Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .setComponent(provider)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(update)
        }
    }

    private companion object {
        const val CHANNEL = "cupola/outside"
        const val FOLDER = "outside"
    }
}
