package com.matthwlabs.cupola.outside

import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

/**
 * The file the app writes for the widgets, as Kotlin reads it: a mirror of
 * `OutsideSnapshot.toJson()` and the types under it
 * (`lib/features/outside/domain/outside_snapshot.dart`), and of
 * `OutsideSnapshot.swift`. Dart writes every word and the widget only draws the
 * frame whose time has come, so nothing here derives a word, a figure or a
 * time: a key the file does not have is a null here, never a default.
 */

/** The tone of a word or a bar, by name. Red is never one: a widget does not draw it. */
enum class OutsideTone {
    GREEN, AMBER, BLUE, NEUTRAL;

    companion object {
        /** A tone this code does not know is the ink (null), not a file nobody can read. */
        fun named(name: String?): OutsideTone? = when (name) {
            "green" -> GREEN
            "amber" -> AMBER
            "blue" -> BLUE
            "neutral" -> NEUTRAL
            else -> null
        }
    }
}

/** One thing in a widget: a title to come, a download, a request. */
data class OutsideItem(
    val title: String,
    val eyebrow: String? = null,
    val words: String? = null,
    val tone: OutsideTone? = null,
    /** How far it got, 0 to 1; null draws no bar. */
    val progress: Double? = null,
    /** File names in `outside_pictures/`. */
    val poster: String? = null,
    val backdrop: String? = null,
    /** A location of the app's router (`OutsideLink`). */
    val route: String? = null,
)

/** What one widget draws at one moment, in every size. */
data class OutsideFace(
    val title: String,
    val subtitle: String? = null,
    val figure: String? = null,
    val figureWords: String? = null,
    val lead: OutsideItem? = null,
    val items: List<OutsideItem> = emptyList(),
    val calm: String? = null,
    /** `As of 14:02`. */
    val age: String,
    /** Old enough that the small widget gives a line to its age. */
    val aged: Boolean,
    val route: String? = null,
)

/** A face and the instant, in epoch milliseconds, from which it is the true one. */
data class OutsideFrame(val from: Long, val face: OutsideFace)

class OutsideSnapshot(
    val takenAt: Long,
    val audience: String,
    /** Each widget's frames by [OutsideKind.key], in time order; a widget this person has nothing for is absent. */
    val widgets: Map<String, List<OutsideFrame>>,
) {
    companion object {
        /**
         * The shape of the file this code reads. Any other reads as no
         * snapshot: a widget draws nothing rather than misread a file it does
         * not know.
         */
        const val VERSION = 1

        /** The snapshot [text] is, or null when it is not one this code reads. */
        fun parse(text: String): OutsideSnapshot? = try {
            val json = JSONObject(text)
            if (json.getInt("version") != VERSION) {
                null
            } else {
                val widgets = json.getJSONObject("widgets")
                OutsideSnapshot(
                    takenAt = OutsideDate.parse(json.getString("takenAt"))
                        ?: throw JSONException("takenAt is not an instant"),
                    audience = json.getString("audience"),
                    widgets = widgets.keys().asSequence().associateWith { key ->
                        val frames = widgets.getJSONArray(key)
                        (0 until frames.length())
                            .map { frame(frames.getJSONObject(it)) }
                            .sortedBy { it.from }
                    },
                )
            }
        } catch (e: JSONException) {
            null
        }

        private fun frame(json: JSONObject) = OutsideFrame(
            from = OutsideDate.parse(json.getString("from"))
                ?: throw JSONException("from is not an instant"),
            face = face(json.getJSONObject("face")),
        )

        private fun face(json: JSONObject): OutsideFace {
            val items = json.getJSONArray("items")
            return OutsideFace(
                title = json.getString("title"),
                subtitle = json.text("subtitle"),
                figure = json.text("figure"),
                figureWords = json.text("figureWords"),
                lead = if (json.isNull("lead")) null else item(json.getJSONObject("lead")),
                items = (0 until items.length()).map { item(items.getJSONObject(it)) },
                calm = json.text("calm"),
                age = json.getString("age"),
                aged = json.getBoolean("aged"),
                route = json.text("route"),
            )
        }

        private fun item(json: JSONObject) = OutsideItem(
            title = json.getString("title"),
            eyebrow = json.text("eyebrow"),
            words = json.text("words"),
            tone = OutsideTone.named(json.text("tone")),
            progress = if (json.isNull("progress")) null else json.getDouble("progress"),
            poster = json.text("poster"),
            backdrop = json.text("backdrop"),
            route = json.text("route"),
        )

        /** Absent and JSON null are the same here: `optString` would answer "null" for a null. */
        private fun JSONObject.text(key: String): String? =
            if (isNull(key)) null else getString(key)
    }
}

/**
 * The instants Dart writes: `DateTime.toUtc().toIso8601String()`, which is
 * `2026-10-16T14:02:00.000Z` for a whole millisecond and
 * `2026-10-16T14:02:00.123456Z` otherwise, up to six fractional digits.
 * `java.time` takes any number of them (the app has core-library desugaring, so
 * it works from API 24), and an offset in place of the `Z` too: no digit count
 * makes a frame vanish.
 */
object OutsideDate {
    /** [text] as epoch milliseconds, or null when it is not an ISO 8601 instant. */
    fun parse(text: String): Long? = try {
        Instant.parse(text).toEpochMilli()
    } catch (e: DateTimeParseException) {
        try {
            OffsetDateTime.parse(text).toInstant().toEpochMilli()
        } catch (e: DateTimeParseException) {
            null
        }
    }
}
