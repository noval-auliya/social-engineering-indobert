package com.example.social_engineering_detector

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Platform channel aplikasi. Didaftarkan di setiap mesin Flutter: mesin UI
 * (MainActivity) dan mesin latar belakang (BackgroundScanner), sehingga
 * kode Dart yang sama bisa berjalan di keduanya.
 */
object AppChannels {
    private val apkExecutor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Handle untuk melepas pendaftaran saat mesin Flutter dihancurkan. */
    class Registration internal constructor(private val onDispose: () -> Unit) {
        fun dispose() = onDispose()
    }

    /**
     * [launchTarget] mengembalikan & menghapus tab tujuan dari notifikasi
     * (hanya untuk mesin UI). [onBackgroundIdle] dipanggil saat mesin latar
     * belakang selesai memproses antrean.
     */
    fun register(
        context: Context,
        messenger: BinaryMessenger,
        launchTarget: (() -> String?)? = null,
        onBackgroundIdle: (() -> Unit)? = null,
    ): Registration {
        val app = context.applicationContext

        MethodChannel(messenger, "sed/wa_listener").setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(
                    mapOf(
                        "granted" to isListenerGranted(app),
                        "enabled" to WaListenerStore.isEnabled(app),
                        "minLength" to WaListenerStore.minLength(app),
                        "alerts" to WaListenerStore.alertsEnabled(app),
                    )
                )
                "openSettings" -> {
                    app.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "setConfig" -> {
                    WaListenerStore.setConfig(
                        app,
                        call.argument<Boolean>("enabled") ?: true,
                        call.argument<Int>("minLength") ?: WaListenerStore.DEFAULT_MIN_LENGTH,
                        call.argument<Boolean>("alerts") ?: true,
                    )
                    result.success(null)
                }
                "drain" -> result.success(WaListenerStore.drain(app))
                "showRiskAlert" -> {
                    RiskNotifier.show(
                        app,
                        id = call.argument<Int>("id") ?: 0,
                        title = call.argument<String>("title").orEmpty(),
                        body = call.argument<String>("body").orEmpty(),
                    )
                    result.success(null)
                }
                "consumeLaunchTarget" -> result.success(launchTarget?.invoke())
                "backgroundIdle" -> {
                    onBackgroundIdle?.invoke()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Analisis APK berat (baca file besar + parsing DEX): jalankan di thread lain.
        MethodChannel(messenger, "sed/apk_analyzer").setMethodCallHandler { call, result ->
            // Lokasi APK aplikasi ini sendiri: dipakai integration test untuk menguji
            // ekstraktor pada APK asli tanpa perlu file dari luar.
            if (call.method == "selfApkPath") {
                return@setMethodCallHandler result.success(app.applicationInfo.sourceDir)
            }
            if (call.method != "analyze") return@setMethodCallHandler result.notImplemented()
            val source = call.argument<String>("source")!!
            val apis = call.argument<List<String>>("apiFeatures").orEmpty()
            apkExecutor.execute {
                val outcome = runCatching { ApkAnalyzer.analyze(app, source, apis) }
                main.post {
                    outcome.fold(
                        { result.success(it) },
                        { result.error("APK_ANALYSIS_FAILED", it.message ?: "$it", null) },
                    )
                }
            }
        }

        var listener: (() -> Unit)? = null
        EventChannel(messenger, "sed/wa_listener/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    listener?.let(WaListenerStore::removeListener)
                    listener = { events.success(1) }.also(WaListenerStore::addListener)
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let(WaListenerStore::removeListener)
                    listener = null
                }
            }
        )

        return Registration {
            listener?.let(WaListenerStore::removeListener)
            listener = null
        }
    }

    private fun isListenerGranted(context: Context): Boolean {
        val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            ?: return false
        val me = ComponentName(context, WaNotificationListener::class.java)
        return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
    }
}
