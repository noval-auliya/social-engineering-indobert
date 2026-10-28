package com.example.social_engineering_detector

import android.app.Notification
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Membaca notifikasi WhatsApp / WhatsApp Business, mengambil teks pesan
 * secara utuh, lalu memasukkan pesan yang cukup panjang ke antrean scan.
 */
class WaNotificationListener : NotificationListenerService() {

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListenerConnected() {
        // Notifikasi WhatsApp menumpuk pesan lama yang belum dibaca; hanya
        // pesan yang masuk setelah listener aktif yang dianggap "sekarang".
        WaListenerStore.markStartNow(this)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in WA_PACKAGES) return
        if (!WaListenerStore.isEnabled(this)) return
        // Ringkasan grup ("5 pesan dari 2 chat") bukan isi pesan.
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val minLength = WaListenerStore.minLength(this)
        val since = WaListenerStore.since(this)
        var added = false
        for (msg in extractMessages(sbn)) {
            if (msg.timestamp < since) continue
            if (msg.text.trim().length < minLength) continue
            if (WaListenerStore.add(this, msg)) added = true
        }
        if (added) mainHandler.post { WaListenerStore.onNewMessage?.invoke() }
    }

    private fun extractMessages(sbn: StatusBarNotification): List<CapturedMessage> {
        val extras = sbn.notification.extras
        val conversation = (extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString().orEmpty()

        // MessagingStyle menyimpan tiap pesan secara utuh (tidak terpotong).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            val bundles = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            if (!bundles.isNullOrEmpty()) {
                return Notification.MessagingStyle.Message.getMessagesFromBundleArray(bundles)
                    .mapNotNull { m ->
                        val text = m.text?.toString() ?: return@mapNotNull null
                        // Pengirim null = pesan milik pengguna sendiri, lewati.
                        @Suppress("DEPRECATION")
                        val sender = (m.senderPerson?.name ?: m.sender)?.toString()
                            ?: return@mapNotNull null
                        CapturedMessage(
                            packageName = sbn.packageName,
                            conversation = conversation,
                            sender = sender,
                            text = text,
                            timestamp = m.timestamp,
                            dedupeKey = "${sbn.packageName}|$conversation|$sender|${m.timestamp}|${text.hashCode()}",
                        )
                    }
            }
        }

        // Fallback: bigText berisi teks lengkap, EXTRA_TEXT bisa terpotong.
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()
            ?: return emptyList()
        return listOf(
            CapturedMessage(
                packageName = sbn.packageName,
                conversation = conversation,
                sender = conversation,
                text = text,
                timestamp = sbn.postTime,
                // Tanpa timestamp: WhatsApp memposting ulang notifikasi yang sama.
                dedupeKey = "${sbn.packageName}|$conversation|${text.hashCode()}",
            )
        )
    }

    companion object {
        private val WA_PACKAGES = setOf("com.whatsapp", "com.whatsapp.w4b")
    }
}
