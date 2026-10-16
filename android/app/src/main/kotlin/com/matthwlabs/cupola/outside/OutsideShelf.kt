package com.matthwlabs.cupola.outside

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import java.io.File
import java.io.IOException

/**
 * Where the app writes what the widgets draw (`outside_shelf.dart`): the
 * snapshot, and the pictures it names beside it.
 *
 * Android has no App Group: the widgets run in the app's own process and read
 * its own folder, `filesDir/outside`, which is also where
 * `getApplicationSupportDirectory()` points and what the `outside_channel`
 * plugin answers `sharedFolder` with. Keep the three in step.
 */
object OutsideShelf {
    private const val FOLDER = "outside"
    private const val SNAPSHOT = "outside.json"
    private const val PICTURES = "outside_pictures"

    private fun folder(context: Context) = File(context.filesDir, FOLDER)

    /**
     * The snapshot on disk, or null when there is none or it is not one this
     * code reads (another version, a file half written, nothing at all). The app
     * writes it whole or not at all (`_writeAtomically`), so a read in the
     * middle of a write reads the file before.
     */
    fun read(context: Context): OutsideSnapshot? = try {
        OutsideSnapshot.parse(File(folder(context), SNAPSHOT).readText())
    } catch (e: IOException) {
        null
    }

    /**
     * The picture [name] in `outside_pictures/`, drawn to cover a
     * [widthPx] by [heightPx] box (the way `centerCrop` does) with its corners
     * rounded by [radiusPx], in a bitmap of exactly that size, or null when
     * there is none that decodes or no room for it in [bitmaps].
     *
     * A widget's pictures travel to the launcher inside the `RemoteViews`, and
     * the system refuses an update whose bitmaps are too many bytes (six per
     * pixel of the screen). So a picture is decoded no larger than it is drawn
     * (`inSampleSize` decodes straight to a power of two at or above the size
     * needed, never the whole file) and then drawn once into the box, with the
     * rounding in the bitmap itself: a launcher cannot clip a child view
     * before Android 12, so the corner is the picture's own on every API.
     */
    fun picture(
        context: Context,
        name: String,
        widthPx: Int,
        heightPx: Int,
        radiusPx: Float,
        bitmaps: OutsideBitmaps,
    ): Bitmap? {
        if (name.isEmpty() || name.contains('/') || name.startsWith('.')) return null
        if (widthPx <= 0 || heightPx <= 0) return null
        val file = File(File(folder(context), PICTURES), name)
        if (!file.isFile) return null
        return bitmaps.cached("$name:$widthPx:$heightPx:$radiusPx") {
            decode(file, widthPx, heightPx, radiusPx, bitmaps)
        }
    }

    private fun decode(
        file: File,
        widthPx: Int,
        heightPx: Int,
        radiusPx: Float,
        bitmaps: OutsideBitmaps,
    ): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        // The scale at which the picture covers the box; the decode is the
        // largest power of two of reduction that does not go under it.
        val cover = maxOf(
            widthPx.toFloat() / bounds.outWidth,
            heightPx.toFloat() / bounds.outHeight,
        )
        var sample = 1
        while (cover * sample * 2 <= 1f) sample *= 2
        if (!bitmaps.take(widthPx, heightPx)) return null
        return try {
            val source = BitmapFactory.decodeFile(
                file.path,
                BitmapFactory.Options().apply {
                    inSampleSize = sample
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                },
            ) ?: return null
            val box = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
            // No density: the launcher draws the bitmap pixel for pixel in the
            // view, and a density here would scale it again.
            box.density = Bitmap.DENSITY_NONE
            val scale = maxOf(
                widthPx.toFloat() / source.width,
                heightPx.toFloat() / source.height,
            )
            val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            shader.setLocalMatrix(
                Matrix().apply {
                    setScale(scale, scale)
                    postTranslate(
                        (widthPx - source.width * scale) / 2f,
                        (heightPx - source.height * scale) / 2f,
                    )
                },
            )
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                this.shader = shader
            }
            Canvas(box).drawRoundRect(
                RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()),
                radiusPx,
                radiusPx,
                paint,
            )
            source.recycle()
            box
        } catch (e: OutOfMemoryError) {
            // A widget lives in the app's own process, which has the room; but
            // a picture that does not fit is a widget without it, never a
            // widget that does not draw.
            null
        }
    }
}

/**
 * The bitmaps of one drawing, and how many bytes they are: a widget's update
 * is refused whole when the bitmaps in its `RemoteViews` come to more than six
 * bytes per pixel of the screen (a screen and a half at four bytes a pixel), so
 * a drawing keeps to half of that and goes without the pictures that would not
 * fit. A picture asked for twice at one size (two sizes of one widget share
 * their artwork) is decoded once and counted once.
 */
class OutsideBitmaps(context: Context) {
    private val limit: Long = context.resources.displayMetrics.let {
        3L * it.widthPixels * it.heightPixels
    }
    private var used = 0L
    private val kept = HashMap<String, Bitmap?>()

    fun take(widthPx: Int, heightPx: Int): Boolean {
        val bytes = 4L * widthPx * heightPx
        if (used + bytes > limit) return false
        used += bytes
        return true
    }

    fun cached(key: String, make: () -> Bitmap?): Bitmap? =
        if (kept.containsKey(key)) kept[key] else make().also { kept[key] = it }
}
