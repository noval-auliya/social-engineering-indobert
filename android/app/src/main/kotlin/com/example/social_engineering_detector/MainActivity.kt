package com.example.social_engineering_detector

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val apkExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "sed/wa_listener").setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(
                    mapOf(
                        "granted" to isListenerGranted(),
                        "enabled" to WaListenerStore.isEnabled(this),
                        "minLength" to WaListenerStore.minLength(this),
                    )
                )
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "setConfig" -> {
                    WaListenerStore.setConfig(
                        this,
                        call.argument<Boolean>("enabled") ?: true,
                        call.argument<Int>("minLength") ?: WaListenerStore.DEFAULT_MIN_LENGTH,
                    )
                    result.success(null)
                }
                "drain" -> result.success(WaListenerStore.drain(this))
                else -> result.notImplemented()
            }
        }

        // Analisis APK berat (baca file besar + parsing DEX): jalankan di thread lain.
        MethodChannel(messenger, "sed/apk_analyzer").setMethodCallHandler { call, result ->
            // Lokasi APK aplikasi ini sendiri: dipakai integration test untuk menguji
            // ekstraktor pada APK asli tanpa perlu file dari luar.
            if (call.method == "selfApkPath") {
                return@setMethodCallHandler result.success(applicationInfo.sourceDir)
            }
            if (call.method != "analyze") return@setMethodCallHandler result.notImplemented()
            val source = call.argument<String>("source")!!
            val apis = call.argument<List<String>>("apiFeatures").orEmpty()
            apkExecutor.execute {
                val outcome = runCatching { ApkAnalyzer.analyze(applicationContext, source, apis) }
                runOnUiThread {
                    outcome.fold(
                        { result.success(it) },
                        { result.error("APK_ANALYSIS_FAILED", it.message ?: "$it", null) },
                    )
                }
            }
        }

        EventChannel(messenger, "sed/wa_listener/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    WaListenerStore.onNewMessage = { events.success(1) }
                }

                override fun onCancel(arguments: Any?) {
                    WaListenerStore.onNewMessage = null
                }
            }
        )
    }

    private fun isListenerGranted(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        val me = ComponentName(this, WaNotificationListener::class.java)
        return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
    }
}
