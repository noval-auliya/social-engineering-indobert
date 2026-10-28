package com.example.social_engineering_detector

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/** Notifikasi sistem untuk pesan WhatsApp yang terindikasi berbahaya. */
object RiskNotifier {
    private const val CHANNEL_ID = "risk_alerts"
    const val EXTRA_OPEN_TAB = "open_tab"

    fun show(context: Context, id: Int, title: String, body: String) {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Peringatan pesan berisiko",
                    NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Pesan WhatsApp yang terindikasi penipuan / social engineering"
                }
            )
        }
        val open = PendingIntent.getActivity(
            context, id,
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_OPEN_TAB, "history")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        // Tanpa izin POST_NOTIFICATIONS (Android 13+) sistem diam-diam menolak.
        runCatching { nm.notify(id, notification) }
    }
}
