package com.example.empty_player

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.empty_player/pip"
    private val INTENT_CHANNEL = "com.example.empty_player/intent"
    private var methodChannel: MethodChannel? = null
    private var intentChannel: MethodChannel? = null
    private var isInPipMode = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipAvailable" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }
                "enterPipMode" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(16, 9))
                            .build()
                        val entered = enterPictureInPictureMode(params)
                        result.success(entered)
                    } else {
                        result.error("UNAVAILABLE", "PiP not available", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Intent channel for opening videos via external intents
        intentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL)
        // Send any initial intent data to Flutter
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(incoming: Intent?) {
        if (incoming == null) return
        val action = incoming.action
        if (action == Intent.ACTION_VIEW || action == Intent.ACTION_SEND) {
            val dataUri: Uri? = incoming.data ?: incoming.clipData?.getItemAt(0)?.uri
            dataUri?.let { uri ->
                // Notify Flutter side to open this video
                intentChannel?.invokeMethod("openVideo", uri.toString())
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPipMode = isInPictureInPictureMode
        
        // Notify Flutter about PiP state change
        methodChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
    
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Optionally auto-enter PiP when user presses home
        // if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isInPipMode) {
        //     val params = PictureInPictureParams.Builder()
        //         .setAspectRatio(Rational(16, 9))
        //         .build()
        //     enterPictureInPictureMode(params)
        // }
    }
}
