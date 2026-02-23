package com.example.empty_player

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.content.res.Configuration
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.util.Rational
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.media.session.MediaButtonReceiver
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.empty_player/pip"
    private val INTENT_CHANNEL = "com.example.empty_player/intent"
    private val EMBEDDING_CHANNEL = "com.example.empty_player/embedding"
    private val TRANSPORT_CHANNEL = "com.example.empty_player/transport"
    private val TRANSPORT_NOTIFICATION_CHANNEL_ID = "empty_player_transport"
    private val TRANSPORT_NOTIFICATION_ID = 44091
    private var methodChannel: MethodChannel? = null
    private var intentChannel: MethodChannel? = null
    private var embeddingChannel: MethodChannel? = null
    private var transportChannel: MethodChannel? = null
    private var mediaSession: MediaSessionCompat? = null
    private var isInPipMode = false
    private var transportState = TransportState()
    private val embeddingEngine by lazy { AndroidMultimodalEmbeddingEngine(applicationContext) }

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

        embeddingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EMBEDDING_CHANNEL)
        embeddingChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "runtimeStatus" -> {
                    Thread {
                        try {
                            val status = embeddingRuntimeStatus()
                            runOnUiThread { result.success(status) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "RUNTIME_STATUS_FAILED",
                                    error.message ?: "Failed to load embedding runtime status.",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                "isReady" -> {
                    Thread {
                        try {
                            val ready = isEmbeddingRuntimeReady()
                            runOnUiThread { result.success(ready) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "RUNTIME_READY_CHECK_FAILED",
                                    error.message ?: "Failed to check embedding runtime readiness.",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                "embedText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val dimensions = call.argument<Int>("dimensions") ?: 128
                    Thread {
                        try {
                            if (!isEmbeddingRuntimeReady()) {
                                val status = embeddingRuntimeStatus()
                                runOnUiThread {
                                    result.error(
                                        "EMBEDDING_UNAVAILABLE",
                                        "On-device multimodal model is unavailable on this build.",
                                        status,
                                    )
                                }
                                return@Thread
                            }
                            val vector = embedTextLocally(text, dimensions)
                            runOnUiThread { result.success(vector) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "EMBED_TEXT_FAILED",
                                    error.message ?: "Failed to extract text embedding",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                "embedFrame" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val timestampMs = call.argument<Number>("timestampMs")?.toLong() ?: 0L
                    val dimensions = call.argument<Int>("dimensions") ?: 128

                    if (sourcePath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "sourcePath is required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            if (!isEmbeddingRuntimeReady()) {
                                val status = embeddingRuntimeStatus()
                                runOnUiThread {
                                    result.error(
                                        "EMBEDDING_UNAVAILABLE",
                                        "On-device multimodal model is unavailable on this build.",
                                        status,
                                    )
                                }
                                return@Thread
                            }
                            val vector = embedFrameLocally(sourcePath, timestampMs, dimensions)
                            runOnUiThread { result.success(vector) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "EMBED_FRAME_FAILED",
                                    error.message ?: "Failed to extract frame embedding",
                                    null
                                )
                            }
                        }
                    }.start()
                }
                "embedImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val dimensions = call.argument<Int>("dimensions") ?: 128

                    if (imagePath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "imagePath is required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            if (!isEmbeddingRuntimeReady()) {
                                val status = embeddingRuntimeStatus()
                                runOnUiThread {
                                    result.error(
                                        "EMBEDDING_UNAVAILABLE",
                                        "On-device multimodal model is unavailable on this build.",
                                        status,
                                    )
                                }
                                return@Thread
                            }
                            val vector = embedImageLocally(imagePath, dimensions)
                            runOnUiThread { result.success(vector) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "EMBED_IMAGE_FAILED",
                                    error.message ?: "Failed to extract image embedding",
                                    null
                                )
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        transportChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRANSPORT_CHANNEL)
        transportChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateTransportState" -> {
                    updateTransportState(call.arguments)
                    result.success(null)
                }
                "disableTransport" -> {
                    disableTransportState()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isEmbeddingRuntimeReady(): Boolean {
        return embeddingEngine.runtimeStatus().ready
    }

    private fun embeddingRuntimeStatus(): Map<String, Any?> {
        return embeddingEngine.runtimeStatus().toMap()
    }

    private fun embedTextLocally(text: String, dimensions: Int): List<Double> {
        return embeddingEngine.embedText(text, dimensions)
    }

    private fun embedFrameLocally(
        sourcePath: String,
        timestampMs: Long,
        dimensions: Int,
    ): List<Double> {
        return embeddingEngine.embedFrame(sourcePath, timestampMs, dimensions)
    }

    private fun embedImageLocally(imagePath: String, dimensions: Int): List<Double> {
        return embeddingEngine.embedImage(imagePath, dimensions)
    }

    @Suppress("UNCHECKED_CAST")
    private fun updateTransportState(rawArguments: Any?) {
        val args = rawArguments as? Map<String, Any?> ?: return
        val title = (args["title"] as? String).orEmpty()
        val sessionId = (args["sessionId"] as? String).orEmpty()
        val durationMs = (args["durationMs"] as? Number)?.toLong() ?: 0L
        val positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L
        val isPlaying = (args["isPlaying"] as? Boolean) ?: false
        val isBuffering = (args["isBuffering"] as? Boolean) ?: false

        transportState = TransportState(
            sessionId = sessionId,
            title = title,
            durationMs = durationMs,
            positionMs = positionMs,
            isPlaying = isPlaying,
            isBuffering = isBuffering,
        )

        ensureMediaSession()
        mediaSession?.isActive = true
        updateMediaSessionMetadata()
        updateMediaSessionPlaybackState()
        publishTransportNotification()
    }

    private fun ensureMediaSession() {
        if (mediaSession != null) return
        mediaSession = MediaSessionCompat(this, "empty_player_transport").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    dispatchTransportAction("play")
                }

                override fun onPause() {
                    dispatchTransportAction("pause")
                }

                override fun onStop() {
                    dispatchTransportAction("stop")
                }

                override fun onFastForward() {
                    dispatchTransportAction("seek_forward")
                }

                override fun onRewind() {
                    dispatchTransportAction("seek_backward")
                }

                override fun onSeekTo(pos: Long) {
                    dispatchTransportAction("seek_to", mapOf("positionMs" to pos))
                }
            })
            isActive = true
        }
    }

    private fun dispatchTransportAction(
        action: String,
        extras: Map<String, Any?> = emptyMap(),
    ) {
        val payload = mutableMapOf<String, Any?>("action" to action)
        payload.putAll(extras)
        runOnUiThread {
            transportChannel?.invokeMethod("onTransportAction", payload)
        }
    }

    private fun updateMediaSessionMetadata() {
        val session = mediaSession ?: return
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, transportState.title)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, transportState.durationMs)
            .build()
        session.setMetadata(metadata)
    }

    private fun updateMediaSessionPlaybackState() {
        val session = mediaSession ?: return
        val state = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_FAST_FORWARD or
                    PlaybackStateCompat.ACTION_REWIND or
                    PlaybackStateCompat.ACTION_SEEK_TO or
                    PlaybackStateCompat.ACTION_STOP
            )
            .setState(
                if (transportState.isPlaying) {
                    PlaybackStateCompat.STATE_PLAYING
                } else {
                    PlaybackStateCompat.STATE_PAUSED
                },
                transportState.positionMs,
                if (transportState.isPlaying) 1.0f else 0.0f,
                SystemClock.elapsedRealtime(),
            )
            .build()
        session.setPlaybackState(state)
    }

    private fun publishTransportNotification() {
        val session = mediaSession ?: return
        if (!canPostNotifications()) {
            return
        }
        ensureTransportNotificationChannel()

        val rewindIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(
            this,
            PlaybackStateCompat.ACTION_REWIND,
        )
        val playPauseIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(
            this,
            if (transportState.isPlaying) {
                PlaybackStateCompat.ACTION_PAUSE
            } else {
                PlaybackStateCompat.ACTION_PLAY
            },
        )
        val forwardIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(
            this,
            PlaybackStateCompat.ACTION_FAST_FORWARD,
        )
        val stopIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(
            this,
            PlaybackStateCompat.ACTION_STOP,
        )

        val contentText = if (transportState.durationMs > 0) {
            "${formatDuration(transportState.positionMs)} / ${formatDuration(transportState.durationMs)}"
        } else {
            formatDuration(transportState.positionMs)
        }

        val notification = NotificationCompat.Builder(this, TRANSPORT_NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(
                if (transportState.isPlaying) {
                    android.R.drawable.ic_media_play
                } else {
                    android.R.drawable.ic_media_pause
                }
            )
            .setContentTitle(transportState.title.ifBlank { "Empty Player" })
            .setContentText(contentText)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(transportState.isPlaying)
            .setContentIntent(createLaunchPendingIntent())
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_rew,
                    "Back 10s",
                    rewindIntent,
                )
            )
            .addAction(
                NotificationCompat.Action(
                    if (transportState.isPlaying) {
                        android.R.drawable.ic_media_pause
                    } else {
                        android.R.drawable.ic_media_play
                    },
                    if (transportState.isPlaying) "Pause" else "Play",
                    playPauseIntent,
                )
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_ff,
                    "Forward 10s",
                    forwardIntent,
                )
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Close",
                    stopIntent,
                )
            )
            .setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
            .build()

        NotificationManagerCompat.from(this).notify(
            TRANSPORT_NOTIFICATION_ID,
            notification,
        )
    }

    private fun createLaunchPendingIntent(): PendingIntent? {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        return PendingIntent.getActivity(
            this,
            1001,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureTransportNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(TRANSPORT_NOTIFICATION_CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            TRANSPORT_NOTIFICATION_CHANNEL_ID,
            "Playback Controls",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Transport controls for active playback sessions"
        }
        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun disableTransportState() {
        transportState = TransportState()
        NotificationManagerCompat.from(this).cancel(TRANSPORT_NOTIFICATION_ID)
        mediaSession?.isActive = false
    }

    private fun clearTransportResources() {
        NotificationManagerCompat.from(this).cancel(TRANSPORT_NOTIFICATION_ID)
        mediaSession?.release()
        mediaSession = null
        transportChannel?.setMethodCallHandler(null)
        transportChannel = null
    }

    private fun formatDuration(durationMs: Long): String {
        val totalSeconds = (durationMs / 1000).coerceAtLeast(0)
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return if (hours > 0) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%02d:%02d", minutes, seconds)
        }
    }

    private fun handleIncomingIntent(incoming: Intent?) {
        if (incoming == null) return
        val action = incoming.action
        if (action == Intent.ACTION_VIEW ||
            action == Intent.ACTION_SEND ||
            action == Intent.ACTION_SEND_MULTIPLE) {
            val dataUri: Uri? = when (action) {
                Intent.ACTION_SEND -> resolveSingleSendUri(incoming)
                Intent.ACTION_SEND_MULTIPLE -> incoming.clipData?.getItemAt(0)?.uri
                else -> incoming.data ?: incoming.clipData?.getItemAt(0)?.uri
            }
            dataUri?.let { uri ->
                // Notify Flutter side to open this video
                intentChannel?.invokeMethod("openVideo", uri.toString())
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun resolveSingleSendUri(intent: Intent): Uri? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                ?: intent.data
                ?: intent.clipData?.getItemAt(0)?.uri
        }
        return (intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
            ?: intent.data
            ?: intent.clipData?.getItemAt(0)?.uri
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

    override fun onDestroy() {
        clearTransportResources()
        super.onDestroy()
    }

    private data class TransportState(
        val sessionId: String = "",
        val title: String = "",
        val durationMs: Long = 0L,
        val positionMs: Long = 0L,
        val isPlaying: Boolean = false,
        val isBuffering: Boolean = false,
    )
}
