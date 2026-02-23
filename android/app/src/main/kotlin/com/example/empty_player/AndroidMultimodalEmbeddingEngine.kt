package com.example.empty_player

import android.content.Context
import io.flutter.FlutterInjector
import org.json.JSONObject
import java.io.InputStream

class AndroidMultimodalEmbeddingEngine(
    private val context: Context,
) {
    data class RuntimeStatus(
        val ready: Boolean,
        val runtimeName: String,
        val provider: String,
        val quantized: Boolean,
        val dimensions: Int,
        val reason: String?,
    ) {
        fun toMap(): Map<String, Any?> {
            return mapOf(
                "ready" to ready,
                "runtimeName" to runtimeName,
                "provider" to provider,
                "quantized" to quantized,
                "dimensions" to dimensions,
                "reason" to reason,
            )
        }
    }

    private sealed interface Delegate {
        fun runtimeStatus(): RuntimeStatus
        fun embedText(query: String, requestedDimensions: Int): List<Double>
        fun embedFrame(sourcePath: String, timestampMs: Long, requestedDimensions: Int): List<Double>
        fun embedImage(imagePath: String, requestedDimensions: Int): List<Double>
    }

    private class OnnxDelegate(
        private val engine: OnnxMultimodalEmbeddingEngine,
    ) : Delegate {
        override fun runtimeStatus(): RuntimeStatus {
            val status = engine.runtimeStatus()
            return RuntimeStatus(
                ready = status.ready,
                runtimeName = status.runtimeName,
                provider = status.provider,
                quantized = status.quantized,
                dimensions = status.dimensions,
                reason = status.reason,
            )
        }

        override fun embedText(query: String, requestedDimensions: Int): List<Double> {
            return engine.embedText(query, requestedDimensions)
        }

        override fun embedFrame(
            sourcePath: String,
            timestampMs: Long,
            requestedDimensions: Int,
        ): List<Double> {
            return engine.embedFrame(sourcePath, timestampMs, requestedDimensions)
        }

        override fun embedImage(imagePath: String, requestedDimensions: Int): List<Double> {
            return engine.embedImage(imagePath, requestedDimensions)
        }
    }

    private class LiteRtDelegate(
        private val engine: LiteRtMultimodalEmbeddingEngine,
    ) : Delegate {
        override fun runtimeStatus(): RuntimeStatus {
            val status = engine.runtimeStatus()
            return RuntimeStatus(
                ready = status.ready,
                runtimeName = status.runtimeName,
                provider = status.provider,
                quantized = status.quantized,
                dimensions = status.dimensions,
                reason = status.reason,
            )
        }

        override fun embedText(query: String, requestedDimensions: Int): List<Double> {
            return engine.embedText(query, requestedDimensions)
        }

        override fun embedFrame(
            sourcePath: String,
            timestampMs: Long,
            requestedDimensions: Int,
        ): List<Double> {
            return engine.embedFrame(sourcePath, timestampMs, requestedDimensions)
        }

        override fun embedImage(imagePath: String, requestedDimensions: Int): List<Double> {
            return engine.embedImage(imagePath, requestedDimensions)
        }
    }

    private data class ManifestProbe(
        val backend: String,
        val textModelAsset: String,
        val visionModelAsset: String,
    )

    private val delegate: Delegate by lazy {
        when (resolveBackend()) {
            "litert" -> LiteRtDelegate(LiteRtMultimodalEmbeddingEngine(context))
            "onnx" -> OnnxDelegate(OnnxMultimodalEmbeddingEngine(context))
            else -> OnnxDelegate(OnnxMultimodalEmbeddingEngine(context))
        }
    }

    fun runtimeStatus(): RuntimeStatus {
        return delegate.runtimeStatus()
    }

    fun embedText(query: String, requestedDimensions: Int): List<Double> {
        return delegate.embedText(query, requestedDimensions)
    }

    fun embedFrame(sourcePath: String, timestampMs: Long, requestedDimensions: Int): List<Double> {
        return delegate.embedFrame(sourcePath, timestampMs, requestedDimensions)
    }

    fun embedImage(imagePath: String, requestedDimensions: Int): List<Double> {
        return delegate.embedImage(imagePath, requestedDimensions)
    }

    private fun resolveBackend(): String {
        val probe = readManifestProbe() ?: return "onnx"
        val normalizedBackend = probe.backend.trim().lowercase()
        if (normalizedBackend == "onnx" || normalizedBackend == "litert") {
            return normalizedBackend
        }

        val textAsset = probe.textModelAsset.lowercase()
        val visionAsset = probe.visionModelAsset.lowercase()
        if (textAsset.endsWith(".tflite") || visionAsset.endsWith(".tflite")) {
            return "litert"
        }
        return "onnx"
    }

    private fun readManifestProbe(): ManifestProbe? {
        return try {
            val raw = readAssetText(MANIFEST_ASSET_PATH)
            val json = JSONObject(raw)
            val textModelAsset = json.optString("textModelAsset").trim()
            val visionModelAsset = json.optString("visionModelAsset").trim()
            ManifestProbe(
                backend = json.optString("backend", "auto"),
                textModelAsset = textModelAsset,
                visionModelAsset = visionModelAsset,
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun readAssetText(assetPath: String): String {
        return openAsset(assetPath).bufferedReader().use { it.readText() }
    }

    private fun openAsset(assetPath: String): InputStream {
        val normalized = assetPath.trim().trimStart('/')
        if (normalized.isEmpty()) {
            throw IllegalArgumentException("Asset path cannot be empty.")
        }

        val loader = FlutterInjector.instance().flutterLoader()
        val withAssetsPrefix = if (normalized.startsWith("assets/")) {
            normalized
        } else {
            "assets/$normalized"
        }

        val candidates = linkedSetOf<String>()
        candidates.add(loader.getLookupKeyForAsset(withAssetsPrefix))
        candidates.add(loader.getLookupKeyForAsset(normalized))
        candidates.add(withAssetsPrefix)
        candidates.add(normalized)
        candidates.add("flutter_assets/$withAssetsPrefix")
        candidates.add("flutter_assets/$normalized")

        var lastError: Exception? = null
        for (candidate in candidates) {
            try {
                return context.assets.open(candidate)
            } catch (error: Exception) {
                lastError = error
            }
        }

        throw IllegalStateException(
            "Asset not found: $assetPath",
            lastError,
        )
    }

    companion object {
        private const val MANIFEST_ASSET_PATH = "assets/models/embedding_manifest.json"
    }
}
