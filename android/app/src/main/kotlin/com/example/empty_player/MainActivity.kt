package com.example.empty_player

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.empty_player/pip"
    private val INTENT_CHANNEL = "com.example.empty_player/intent"
    private val EMBEDDING_CHANNEL = "com.example.empty_player/embedding"
    private var methodChannel: MethodChannel? = null
    private var intentChannel: MethodChannel? = null
    private var embeddingChannel: MethodChannel? = null
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

        embeddingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EMBEDDING_CHANNEL)
        embeddingChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isReady" -> {
                    result.success(true)
                }
                "embedText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val dimensions = call.argument<Int>("dimensions") ?: 128
                    val vector = embedTextLocally(text, dimensions)
                    result.success(vector)
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
    }

    private fun embedTextLocally(text: String, dimensions: Int): List<Double> {
        val safeDimensions = dimensions.coerceIn(32, 512)
        val vector = DoubleArray(safeDimensions)
        val tokens = tokenize(text)

        for (token in tokens) {
            applySemanticTextHints(token, vector)
            val hash = token.hashCode()
            val index = abs(hash) % safeDimensions
            val sign = if ((hash and 1) == 0) 1.0 else -1.0
            vector[index] += 0.06 * sign
        }

        return normalize(vector)
    }

    private fun tokenize(input: String): List<String> {
        return input
            .trim()
            .lowercase(Locale.US)
            .split(Regex("[^a-z0-9]+"))
            .filter { it.isNotBlank() }
    }

    private fun applySemanticTextHints(token: String, vector: DoubleArray) {
        fun add(index: Int, value: Double) {
            if (index in vector.indices) {
                vector[index] += value
            }
        }

        when (token) {
            "red", "fire", "sunset", "warm" -> {
                add(0, 1.0)
                add(23, 0.6)
            }
            "orange", "gold", "yellow" -> {
                add(1, 1.0)
                add(23, 0.5)
            }
            "green", "forest", "grass", "nature" -> {
                add(4, 1.0)
                add(24, 0.6)
            }
            "blue", "ocean", "sea", "water", "sky" -> {
                add(8, 1.0)
                add(25, 0.7)
            }
            "dark", "night", "shadow" -> {
                add(16, 0.8)
                add(17, 0.6)
            }
            "bright", "daylight", "sunny" -> {
                add(18, 0.7)
                add(19, 1.0)
                add(21, 0.6)
            }
            "colorful", "vivid" -> {
                add(14, 0.7)
                add(15, 0.9)
                add(20, 0.6)
            }
            "portrait", "face", "person", "people" -> add(26, 0.8)
            "city", "street", "building", "urban" -> add(22, 0.5)
        }
    }

    private fun embedFrameLocally(
        sourcePath: String,
        timestampMs: Long,
        dimensions: Int,
    ): List<Double> {
        val retriever = MediaMetadataRetriever()

        try {
            val normalized = sourcePath.trim()
            when {
                normalized.startsWith("content://") -> {
                    retriever.setDataSource(this, Uri.parse(normalized))
                }
                normalized.startsWith("file://") -> {
                    val uri = Uri.parse(normalized)
                    val path = uri.path ?: throw IllegalArgumentException("Invalid file URI")
                    retriever.setDataSource(path)
                }
                else -> retriever.setDataSource(normalized)
            }

            val frame = retriever.getFrameAtTime(
                timestampMs * 1000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            ) ?: retriever.getFrameAtTime()
            ?: throw IllegalStateException("Could not decode video frame")

            try {
                return embedBitmap(frame, dimensions.coerceIn(32, 512))
            } finally {
                frame.recycle()
            }
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun embedImageLocally(imagePath: String, dimensions: Int): List<Double> {
        val safeDimensions = dimensions.coerceIn(32, 512)
        val normalized = imagePath.trim()
        val bitmap: Bitmap = when {
            normalized.startsWith("content://") -> {
                val input = contentResolver.openInputStream(Uri.parse(normalized))
                    ?: throw IllegalStateException("Could not open image uri")
                input.use { stream ->
                    BitmapFactory.decodeStream(stream)
                        ?: throw IllegalStateException("Failed to decode image")
                }
            }
            normalized.startsWith("file://") -> {
                val uri = Uri.parse(normalized)
                val path = uri.path ?: throw IllegalArgumentException("Invalid file URI")
                BitmapFactory.decodeFile(path)
                    ?: throw IllegalStateException("Failed to decode image file")
            }
            else -> BitmapFactory.decodeFile(normalized)
                ?: throw IllegalStateException("Failed to decode image file")
        }

        try {
            return embedBitmap(bitmap, safeDimensions)
        } finally {
            bitmap.recycle()
        }
    }

    private fun embedBitmap(bitmap: Bitmap, safeDimensions: Int): List<Double> {
        val vector = DoubleArray(safeDimensions)
        val width = bitmap.width
        val height = bitmap.height
        if (width <= 0 || height <= 0) {
            throw IllegalStateException("Decoded bitmap has invalid dimensions")
        }

        val step = max(1, min(width, height) / 80)
        val hsv = FloatArray(3)

        var sampleCount = 0
        var edgeSamples = 0
        var edgeSum = 0.0

        var y = 0
        while (y < height) {
            var x = 0
            while (x < width) {
                val pixel = bitmap.getPixel(x, y)
                val r = Color.red(pixel).toDouble()
                val g = Color.green(pixel).toDouble()
                val b = Color.blue(pixel).toDouble()
                Color.RGBToHSV(r.toInt(), g.toInt(), b.toInt(), hsv)

                val hueBin = ((hsv[0] / 360.0) * 12).toInt().coerceIn(0, 11)
                val satBin = (hsv[1] * 4).toInt().coerceIn(0, 3)
                val valBin = (hsv[2] * 4).toInt().coerceIn(0, 3)
                addFeature(vector, hueBin, 1.0)
                addFeature(vector, 12 + satBin, 1.0)
                addFeature(vector, 16 + valBin, 1.0)
                addFeature(vector, 20, hsv[1].toDouble())
                addFeature(vector, 21, hsv[2].toDouble())

                val warmth = ((r + g) - (2 * b)) / 255.0
                addFeature(vector, 23, warmth)
                addFeature(vector, 24, g / 255.0)
                addFeature(vector, 25, b / 255.0)

                val maxRgb = max(r, max(g, b))
                val minRgb = min(r, min(g, b))
                val skinLike = (r > 95 && g > 40 && b > 20 && (maxRgb - minRgb) > 15 && abs(r - g) > 15 && r > g && r > b)
                if (skinLike) addFeature(vector, 26, 1.0)

                if (x + step < width) {
                    val next = bitmap.getPixel(x + step, y)
                    val dr = abs(Color.red(next) - Color.red(pixel))
                    val dg = abs(Color.green(next) - Color.green(pixel))
                    val db = abs(Color.blue(next) - Color.blue(pixel))
                    edgeSum += (dr + dg + db) / (255.0 * 3.0)
                    edgeSamples++
                }

                sampleCount++
                x += step
            }
            y += step
        }

        if (sampleCount > 0) {
            for (index in 0..21) {
                if (index in vector.indices) vector[index] /= sampleCount.toDouble()
            }
            if (23 in vector.indices) vector[23] /= sampleCount.toDouble()
            if (24 in vector.indices) vector[24] /= sampleCount.toDouble()
            if (25 in vector.indices) vector[25] /= sampleCount.toDouble()
            if (26 in vector.indices) vector[26] /= sampleCount.toDouble()
        }
        if (22 in vector.indices) {
            vector[22] = if (edgeSamples > 0) edgeSum / edgeSamples.toDouble() else 0.0
        }

        return normalize(vector)
    }

    private fun addFeature(vector: DoubleArray, index: Int, value: Double) {
        if (index in vector.indices) {
            vector[index] += value
        }
    }

    private fun normalize(vector: DoubleArray): List<Double> {
        val magnitude = sqrt(vector.sumOf { it * it })
        if (magnitude <= 1e-9) {
            return vector.toList()
        }
        return vector.map { it / magnitude }
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
}
