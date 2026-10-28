package com.example.social_engineering_detector

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var channels: AppChannels.Registration? = null

    /** Tab tujuan saat dibuka dari notifikasi peringatan, mis. "history". */
    private var launchTarget: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        launchTarget = intent?.getStringExtra(RiskNotifier.EXTRA_OPEN_TAB)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(RiskNotifier.EXTRA_OPEN_TAB)?.let { launchTarget = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channels = AppChannels.register(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            launchTarget = { launchTarget.also { launchTarget = null } },
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channels?.dispose()
        channels = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
