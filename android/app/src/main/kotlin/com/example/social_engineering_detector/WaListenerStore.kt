package com.example.social_engineering_detector

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Pesan WhatsApp yang ditangkap dari notifikasi. */
data class CapturedMessage(
    val packageName: String,
    val conversation: String,
    val sender: String,
    val text: String,
    val timestamp: Long,
    /** Kunci unik agar pesan yang sama tidak di-scan dua kali. */
    val dedupeKey: String,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("package", packageName)
        .put("conversation", conversation)
        .put("sender", sender)
        .put("text", text)
        .put("timestamp", timestamp)
}

/**
 * Antrean pesan + konfigurasi listener, disimpan di SharedPreferences agar
 * pesan tetap tertangkap walaupun UI Flutter sedang tidak berjalan.
 */
object WaListenerStore {
    private const val PREFS = "wa_listener"
    private const val KEY_QUEUE = "queue"
    private const val KEY_SEEN = "seen"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_MIN_LENGTH = "min_length"
    private const val KEY_SINCE = "since"
    private const val KEY_ALERTS = "alerts"
    private const val MAX_QUEUE = 200
    private const val MAX_SEEN = 500

    const val DEFAULT_MIN_LENGTH = 150

    /**
     * Pendengar pesan baru dari setiap mesin Flutter yang hidup (UI dan/atau
     * latar belakang). Yang terakhir didaftarkan yang diberi tahu. Hanya
     * diakses dari main thread.
     */
    private val listeners = ArrayList<() -> Unit>()

    fun addListener(l: () -> Unit) { listeners += l }
    fun removeListener(l: () -> Unit) { listeners.remove(l) }

    /** Memberi tahu mesin Flutter teratas; false jika tidak ada yang hidup. */
    fun notifyNewMessage(): Boolean {
        val top = listeners.lastOrNull() ?: return false
        top()
        return true
    }

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(c: Context) = prefs(c).getBoolean(KEY_ENABLED, true)

    fun minLength(c: Context) = prefs(c).getInt(KEY_MIN_LENGTH, DEFAULT_MIN_LENGTH)

    /** Hanya pesan yang dikirim sejak waktu ini (epoch ms) yang di-scan. */
    fun since(c: Context) = prefs(c).getLong(KEY_SINCE, 0L)

    fun markStartNow(c: Context) {
        prefs(c).edit().putLong(KEY_SINCE, System.currentTimeMillis()).apply()
    }

    /** Scan di latar belakang + notifikasi sistem untuk pesan berisiko. */
    fun alertsEnabled(c: Context) = prefs(c).getBoolean(KEY_ALERTS, true)

    fun setConfig(c: Context, enabled: Boolean, minLength: Int, alerts: Boolean) {
        val turnedOn = enabled && !isEnabled(c)
        prefs(c).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putInt(KEY_MIN_LENGTH, minLength)
            .putBoolean(KEY_ALERTS, alerts)
            .apply()
        // Saat pemantauan diaktifkan ulang, pesan sebelum titik ini diabaikan.
        if (turnedOn) markStartNow(c)
    }

    /** Menambah pesan ke antrean; false jika pesan sudah pernah ditangkap. */
    @Synchronized
    fun add(c: Context, msg: CapturedMessage): Boolean {
        val p = prefs(c)
        val seen = JSONArray(p.getString(KEY_SEEN, "[]"))
        for (i in 0 until seen.length()) {
            if (seen.getString(i) == msg.dedupeKey) return false
        }
        seen.put(msg.dedupeKey)
        while (seen.length() > MAX_SEEN) seen.remove(0)

        val queue = JSONArray(p.getString(KEY_QUEUE, "[]"))
        queue.put(msg.toJson())
        while (queue.length() > MAX_QUEUE) queue.remove(0)

        p.edit()
            .putString(KEY_SEEN, seen.toString())
            .putString(KEY_QUEUE, queue.toString())
            .apply()
        return true
    }

    /** Mengambil semua pesan di antrean lalu mengosongkannya. */
    @Synchronized
    fun drain(c: Context): List<Map<String, Any>> {
        val p = prefs(c)
        val queue = JSONArray(p.getString(KEY_QUEUE, "[]"))
        p.edit().putString(KEY_QUEUE, "[]").apply()
        return (0 until queue.length()).map { i ->
            val o = queue.getJSONObject(i)
            mapOf(
                "package" to o.getString("package"),
                "conversation" to o.getString("conversation"),
                "sender" to o.getString("sender"),
                "text" to o.getString("text"),
                "timestamp" to o.getLong("timestamp"),
            )
        }
    }
}
