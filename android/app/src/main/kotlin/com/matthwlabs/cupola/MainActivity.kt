package com.matthwlabs.cupola

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PersistableBundle
import android.provider.Settings
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CLIPBOARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copySecret" -> {
                        val secret = call.argument<String>("secret")
                        if (secret.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            result.success(copySecret(secret))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCAL_NETWORK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resolve" -> resolveLocalNetwork(result)
                    "openSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TASK_HYGIENE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pruneFinishedWork" -> result.success(pruneFinishedWork())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Drops WorkManager's records of jobs that have already finished.
     *
     * A background release search is a `DataTask`, which the downloader plugin
    * always runs through WorkManager, so the whole task, headers and the arr
     * admin API key with them, is stored as the job's `inputData` in
     * WorkManager's own database. That row outlives the search: the automatic
     * pruning has a **one-day** threshold and runs only when the database next
     * happens to be opened, and the plugin never prunes. Calling this at launch
     * shortens the life of that copy from "at least a day, eventually" to
     * "until the next launch".
     *
     * Two reasons it is safe to be this blunt. It only ever touches jobs in a
    * terminal state (running work is untouched), and Cupola uses neither
     * pause/resume nor `doRescheduleKilledTasks`, so there is no finished record
     * anything here still needs. It also does the plugin a favour: with the work
     * list empty, the plugin's own check for an orphaned `taskMap` becomes true
     * on the following launch and clears the same key from preferences.
     *
     * Not routed through the downloader plugin because it does not expose this;
     * `pruneWork` is WorkManager's own API and this is the only way to reach it.
     */
    private fun pruneFinishedWork(): Boolean {
        return try {
            WorkManager.getInstance(applicationContext).pruneWork()
            true
        } catch (e: IllegalStateException) {
           // WorkManager was never initialised in this process. Nothing has
            // been enqueued, so there is nothing to prune either. Dart treats
            // false as "not done" and simply tries again next launch.
            false
        }
    }

    /**
     * Answers whether Android is letting Cupola onto the local network.
     *
     * Local Network Protections put LAN traffic behind [ACCESS_LOCAL_NETWORK],
     * and a denial does not look like one at the socket: TCP connections simply
     * time out, so a connection test blames the address the user typed. Dart asks
    * only after such a failure, which is why requesting here is not an ambush:
     * the user has just tapped "Test connection" and is watching.
     *
     * `just_granted` is exact rather than inferred on this platform: reaching the
     * request at all proves the permission was missing when the connection was
     * attempted, so a grant means that attempt deserves a retry.
     */
    private fun resolveLocalNetwork(result: MethodChannel.Result) {
        if (!localNetworkIsGated()) {
            result.success(UNRESTRICTED)
            return
        }
        if (checkSelfPermission(ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED) {
            result.success(GRANTED)
            return
        }
        // One dialog answers every caller. Onboarding tests each configured
        // service in parallel, and Android delivers a single result per request
       // code: a second request would strand the first caller for good.
        pendingLocalNetwork.add(result)
        if (pendingLocalNetwork.size == 1) {
            requestPermissions(arrayOf(ACCESS_LOCAL_NETWORK), LOCAL_NETWORK_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCAL_NETWORK_REQUEST) return
        val verdict = when {
           // Dismissed without answering. Android reports that as an empty
            // array. Claiming a denial here would name the wrong cause.
            grantResults.isEmpty() -> UNKNOWN
            grantResults[0] == PackageManager.PERMISSION_GRANTED -> JUST_GRANTED
            else -> DENIED
        }
        val waiting = pendingLocalNetwork.toList()
        pendingLocalNetwork.clear()
        waiting.forEach { it.success(verdict) }
    }

    /**
     * Whether this device and this build are actually subject to the gate.
     *
     * Both halves matter. Below Android 17 nothing enforces it, and an app that
     * targets less than 37 keeps the implicit local-network access that
    * `INTERNET` has always carried, so on every shipping build today this
     * returns false and the whole path stays dormant. It lights up on its own the
     * day `targetSdk` reaches 37, which is exactly when a silent timeout would
     * otherwise start looking like a broken server.
     */
    private fun localNetworkIsGated(): Boolean {
        if (Build.VERSION.SDK_INT < LOCAL_NETWORK_ENFORCED_SDK) return false
        return applicationInfo.targetSdkVersion >= LOCAL_NETWORK_ENFORCED_SDK
    }

    /** Cupola's own page in Settings, where the permission toggle lives. */
    private fun openAppSettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Puts [secret] on the clipboard marked as sensitive.
     *
     * From Android 13 the system shows a preview of every copy, which for a
     * credential means rendering it in cleartext over whatever is on screen.
     * `EXTRA_IS_SENSITIVE` is what suppresses that preview, and it is only
    * reachable through [ClipDescription.setExtras]. Flutter's own clipboard
     * plumbing never sets it.
     *
     * Returns false rather than throwing when there is no clipboard service, so
     * Dart can fall back to the plain copy: an unhardened key on the clipboard
     * is still better than a copy button that does nothing.
     */
    private fun copySecret(secret: String): Boolean {
        val clipboard =
            getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return false

        val clip = ClipData.newPlainText("", secret)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras =
                PersistableBundle().apply {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
        }

        return try {
            clipboard.setPrimaryClip(clip)
            true
        } catch (e: IllegalStateException) {
            // Some OEM builds throw when the app is not the focused window.
            false
        }
    }

    /** The Dart calls waiting on the permission dialog, if one is open. */
    private val pendingLocalNetwork = mutableListOf<MethodChannel.Result>()

    private companion object {
        const val SECURE_CLIPBOARD_CHANNEL = "com.matthwlabs.cupola/secure_clipboard"
        const val LOCAL_NETWORK_CHANNEL = "com.matthwlabs.cupola/local_network"
        const val TASK_HYGIENE_CHANNEL = "com.matthwlabs.cupola/background_task_hygiene"

        /**
         * Spelled out rather than taken from `Manifest.permission`: the constant
         * does not exist below the Android 17 SDK, and the name is stable.
         */
        const val ACCESS_LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"

        /** Android 17. No `Build.VERSION_CODES` constant for it yet. */
        const val LOCAL_NETWORK_ENFORCED_SDK = 37

        const val LOCAL_NETWORK_REQUEST = 0x10CA

        const val UNRESTRICTED = "unrestricted"
        const val GRANTED = "granted"
        const val JUST_GRANTED = "just_granted"
        const val DENIED = "denied"
        const val UNKNOWN = "unknown"
    }
}
