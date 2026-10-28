package com.example.social_engineering_detector

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Menjalankan scan pesan saat aplikasi tertutup: menyalakan mesin Flutter
 * tanpa layar yang menjalankan `backgroundScanMain` (lib/main.dart). Kode
 * analisis Dart yang sama dipakai, tidak ada logika ganda di Kotlin.
 *
 * Mesin dimatikan setelah [IDLE_MS] tanpa pesan baru untuk menghemat baterai
 * dan memori (model IndoBERT ±125 MB).
 */
object BackgroundScanner {
    private const val TAG = "BackgroundScanner"
    private const val IDLE_MS = 60_000L

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channels: AppChannels.Registration? = null
    private val shutdown = Runnable { stop() }

    /** Dipanggil di main thread setiap ada pesan baru di antrean. */
    fun onMessagesQueued(context: Context) {
        main.removeCallbacks(shutdown)
        // Mesin UI atau mesin latar belakang yang sudah hidup akan memproses.
        if (WaListenerStore.notifyNewMessage()) return
        // Sedang menyala: Dart akan menguras antrean begitu siap.
        if (engine != null) return
        // Peringatan dimatikan: pesan menunggu sampai aplikasi dibuka.
        if (!WaListenerStore.alertsEnabled(context)) return
        start(context.applicationContext)
    }

    private fun start(app: Context) {
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)
            val e = FlutterEngine(app)
            channels = AppChannels.register(
                app,
                e.dartExecutor.binaryMessenger,
                onBackgroundIdle = {
                    main.removeCallbacks(shutdown)
                    main.postDelayed(shutdown, IDLE_MS)
                },
            )
            e.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundScanMain")
            )
            engine = e
            Log.i(TAG, "Mesin Flutter latar belakang dinyalakan")
        } catch (t: Throwable) {
            Log.e(TAG, "Gagal menyalakan scan latar belakang", t)
            stop()
        }
    }

    private fun stop() {
        channels?.dispose()
        channels = null
        engine?.destroy()
        if (engine != null) Log.i(TAG, "Mesin Flutter latar belakang dimatikan")
        engine = null
    }
}
