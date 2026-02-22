package com.example.empty_player

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

class OnnxMultimodalEmbeddingEngine(
    private val context: Context,
) {
    private val environment: OrtEnvironment = OrtEnvironment.getEnvironment()

    @Volatile
    private var initialized = false
    private var initError: String? = null

    private var runtimeName: String = "embedding_unavailable"
    private var provider: String = "none"
    private var quantized: Boolean = false
    private var dimensions: Int = 0

    private var textModelAsset: String? = null
    private var visionModelAsset: String? = null

    private var imageInputSize: Int = 224
    private var imageMean: FloatArray = floatArrayOf(0.48145466f, 0.4578275f, 0.40821073f)
    private var imageStd: FloatArray = floatArrayOf(0.26862954f, 0.26130258f, 0.27577711f)

    private var textSession: OrtSession? = null
    private var visionSession: OrtSession? = null

    private var tokenizer: ClipBPETokenizer? = null

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

    fun runtimeStatus(): RuntimeStatus {
        ensureInitialized()
        val ready = textSession != null && visionSession != null && tokenizer != null
        return RuntimeStatus(
            ready = ready,
            runtimeName = runtimeName,
            provider = provider,
            quantized = quantized,
            dimensions = dimensions,
            reason = if (ready) null else (initError ?: "Embedding runtime is not initialized."),
        )
    }

    fun embedText(query: String, requestedDimensions: Int): List<Double> {
        ensureReady()
        val localTokenizer = tokenizer ?: throw IllegalStateException("Tokenizer unavailable")
        val localSession = textSession ?: throw IllegalStateException("Text model unavailable")

        val inputIds = localTokenizer.encode(query)
        val inputName = localSession.inputNames.firstOrNull()
            ?: throw IllegalStateException("Text model has no input tensor")

        val inputTensor = OnnxTensor.createTensor(
            environment,
            LongBuffer.wrap(inputIds),
            longArrayOf(1, inputIds.size.toLong()),
        )
        val vector = try {
            val result = localSession.run(mapOf(inputName to inputTensor))
            try {
                if (result.size() <= 0) {
                    throw IllegalStateException("Text model returned no output")
                }
                val outputTensor = result.get(0) as? OnnxTensor
                    ?: throw IllegalStateException("Text model output is not a tensor")
                extractEmbeddingVector(outputTensor)
            } finally {
                result.close()
            }
        } finally {
            inputTensor.close()
        }

        return resizeAndNormalize(vector, requestedDimensions)
    }

    fun embedFrame(
        sourcePath: String,
        timestampMs: Long,
        requestedDimensions: Int,
    ): List<Double> {
        val retriever = MediaMetadataRetriever()
        try {
            val normalized = sourcePath.trim()
            when {
                normalized.startsWith("content://") -> {
                    retriever.setDataSource(context, Uri.parse(normalized))
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
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: retriever.getFrameAtTime()
            ?: throw IllegalStateException("Could not decode video frame")

            return try {
                embedBitmap(frame, requestedDimensions)
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

    fun embedImage(imagePath: String, requestedDimensions: Int): List<Double> {
        val normalized = imagePath.trim()
        val bitmap: Bitmap = when {
            normalized.startsWith("content://") -> {
                val input = context.contentResolver.openInputStream(Uri.parse(normalized))
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

        return try {
            embedBitmap(bitmap, requestedDimensions)
        } finally {
            bitmap.recycle()
        }
    }

    private fun embedBitmap(bitmap: Bitmap, requestedDimensions: Int): List<Double> {
        ensureReady()
        val localVisionSession = visionSession ?: throw IllegalStateException("Vision model unavailable")

        val inputInfo = localVisionSession.inputInfo.values.firstOrNull()?.info as? TensorInfo
            ?: throw IllegalStateException("Vision model input metadata unavailable")
        val inputName = localVisionSession.inputNames.firstOrNull()
            ?: throw IllegalStateException("Vision model has no input tensor")
        val shape = inputInfo.shape

        val tensorData = buildImageTensor(bitmap, shape)
        val inputTensor = OnnxTensor.createTensor(
            environment,
            FloatBuffer.wrap(tensorData.data),
            tensorData.shape,
        )

        val vector = try {
            val result = localVisionSession.run(mapOf(inputName to inputTensor))
            try {
                if (result.size() <= 0) {
                    throw IllegalStateException("Vision model returned no output")
                }
                val outputTensor = result.get(0) as? OnnxTensor
                    ?: throw IllegalStateException("Vision model output is not a tensor")
                extractEmbeddingVector(outputTensor)
            } finally {
                result.close()
            }
        } finally {
            inputTensor.close()
        }

        return resizeAndNormalize(vector, requestedDimensions)
    }

    private fun ensureReady() {
        ensureInitialized()
        val ready = textSession != null && visionSession != null && tokenizer != null
        if (!ready) {
            throw IllegalStateException(initError ?: "Embedding runtime is unavailable.")
        }
    }

    private fun ensureInitialized() {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            initialize()
            initialized = true
        }
    }

    private fun initialize() {
        try {
            val manifest = loadManifest()
            runtimeName = manifest.runtimeName
            quantized = manifest.quantized
            dimensions = manifest.dimensions
            imageInputSize = manifest.imageInputSize
            imageMean = manifest.imageMean
            imageStd = manifest.imageStd
            textModelAsset = manifest.textModelAsset
            visionModelAsset = manifest.visionModelAsset

            val vocab = loadVocab(manifest.vocabAsset)
            val merges = loadMerges(manifest.mergesAsset)
            tokenizer = ClipBPETokenizer(
                vocab = vocab,
                merges = merges,
                contextLength = manifest.contextLength,
            )

            val options = OrtSession.SessionOptions().apply {
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                setIntraOpNumThreads(2)
                setInterOpNumThreads(1)
            }
            val nnapiEnabled = tryEnableNnapi(options)
            provider = if (nnapiEnabled) "onnxruntime_nnapi" else "onnxruntime_cpu"

            val textModelPath = copyAssetToCache(manifest.textModelAsset)
            val visionModelPath = copyAssetToCache(manifest.visionModelAsset)

            try {
                textSession = environment.createSession(textModelPath.absolutePath, options)
                visionSession = environment.createSession(visionModelPath.absolutePath, options)
            } catch (_: Exception) {
                // A partial/corrupt cached model can happen if the process is interrupted mid-copy.
                // Force a recopy once before failing initialization.
                textSession?.close()
                visionSession?.close()
                textSession = null
                visionSession = null

                val freshTextPath = copyAssetToCache(manifest.textModelAsset, forceRewrite = true)
                val freshVisionPath = copyAssetToCache(manifest.visionModelAsset, forceRewrite = true)
                textSession = environment.createSession(freshTextPath.absolutePath, options)
                visionSession = environment.createSession(freshVisionPath.absolutePath, options)
            }
            initError = null
        } catch (error: Exception) {
            textSession?.close()
            visionSession?.close()
            textSession = null
            visionSession = null
            tokenizer = null
            provider = "none"
            runtimeName = "embedding_unavailable"
            dimensions = 0
            quantized = false
            initError = error.message ?: "Failed to initialize ONNX embedding engine."
        }
    }

    private fun tryEnableNnapi(options: OrtSession.SessionOptions): Boolean {
        return try {
            val method = options.javaClass.methods.firstOrNull {
                it.name == "addNnapi" && it.parameterCount == 0
            }
            if (method != null) {
                method.invoke(options)
                return true
            }

            val methodWithArgs = options.javaClass.methods.firstOrNull {
                it.name == "addNnapi" && it.parameterCount == 1
            }
            if (methodWithArgs != null) {
                val parameter = methodWithArgs.parameterTypes.first()
                if (Map::class.java.isAssignableFrom(parameter)) {
                    methodWithArgs.invoke(options, emptyMap<String, String>())
                } else {
                    methodWithArgs.invoke(options, null)
                }
                return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun copyAssetToCache(
        assetPath: String,
        forceRewrite: Boolean = false,
    ): File {
        val dir = File(context.filesDir, "embedding_models")
        if (!dir.exists()) {
            dir.mkdirs()
        }

        val safeName = assetPath.replace('/', '_')
        val target = File(dir, safeName)
        if (!forceRewrite && target.exists() && target.length() > 0) {
            return target
        }

        val tmp = File(dir, "$safeName.tmp")
        if (tmp.exists()) {
            tmp.delete()
        }

        openAsset(assetPath).use { input ->
            tmp.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        if (tmp.length() <= 0) {
            tmp.delete()
            throw IllegalStateException("Failed to copy asset to cache: $assetPath")
        }

        if (target.exists()) {
            target.delete()
        }
        if (!tmp.renameTo(target)) {
            tmp.inputStream().use { input ->
                target.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            tmp.delete()
        }
        return target
    }

    private fun loadManifest(): EngineManifest {
        val raw = readAssetText(MANIFEST_ASSET_PATH)
        val json = JSONObject(raw)

        val runtimeName = json.optString("runtimeName", "onnx_multimodal")
        val quantized = json.optBoolean("quantized", true)
        val dimensions = json.optInt("dimensions", 512)
        val contextLength = json.optInt("contextLength", 77)

        val textModelAsset = json.optString("textModelAsset").trim()
        val visionModelAsset = json.optString("visionModelAsset").trim()
        if (textModelAsset.isEmpty() || visionModelAsset.isEmpty()) {
            throw IllegalStateException("Manifest is missing model asset paths.")
        }

        val tokenizerJson = json.optJSONObject("tokenizer")
            ?: throw IllegalStateException("Manifest tokenizer config is missing.")
        val vocabAsset = tokenizerJson.optString("vocabAsset").trim()
        val mergesAsset = tokenizerJson.optString("mergesAsset").trim()
        if (vocabAsset.isEmpty() || mergesAsset.isEmpty()) {
            throw IllegalStateException("Manifest tokenizer assets are missing.")
        }

        val imageJson = json.optJSONObject("image")
        val inputSize = imageJson?.optInt("inputSize", 224) ?: 224
        val mean = imageJson?.optJSONArray("mean")?.toFloatArray(3)
            ?: floatArrayOf(0.48145466f, 0.4578275f, 0.40821073f)
        val std = imageJson?.optJSONArray("std")?.toFloatArray(3)
            ?: floatArrayOf(0.26862954f, 0.26130258f, 0.27577711f)

        verifyAssetExists(textModelAsset)
        verifyAssetExists(visionModelAsset)
        verifyAssetExists(vocabAsset)
        verifyAssetExists(mergesAsset)

        return EngineManifest(
            runtimeName = runtimeName,
            quantized = quantized,
            dimensions = dimensions,
            contextLength = contextLength,
            textModelAsset = textModelAsset,
            visionModelAsset = visionModelAsset,
            vocabAsset = vocabAsset,
            mergesAsset = mergesAsset,
            imageInputSize = inputSize,
            imageMean = mean,
            imageStd = std,
        )
    }

    private fun verifyAssetExists(assetPath: String) {
        openAsset(assetPath).use { _ -> }
    }

    private fun loadVocab(assetPath: String): Map<String, Int> {
        val raw = readAssetText(assetPath)
        val json = JSONObject(raw)
        val result = HashMap<String, Int>(json.length())
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = json.getInt(key)
        }
        return result
    }

    private fun loadMerges(assetPath: String): List<Pair<String, String>> {
        val lines = openAsset(assetPath).bufferedReader().use { it.readLines() }
        val merges = ArrayList<Pair<String, String>>(lines.size)
        for (line in lines) {
            val normalized = line.trim()
            if (normalized.isEmpty() || normalized.startsWith("#")) continue
            val parts = normalized.split(' ')
            if (parts.size < 2) continue
            merges.add(parts[0] to parts[1])
        }
        return merges
    }

    private fun extractEmbeddingVector(tensor: OnnxTensor): FloatArray {
        val value = tensor.value
        val flattened = flattenTensorValue(value)
        if (flattened.isEmpty()) {
            throw IllegalStateException("Model returned an empty embedding vector.")
        }
        return flattened
    }

    private fun flattenTensorValue(value: Any?): FloatArray {
        return when (value) {
            is FloatArray -> value
            is Array<*> -> {
                if (value.isEmpty()) {
                    floatArrayOf()
                } else {
                    val first = value.firstOrNull()
                    when (first) {
                        is FloatArray -> first
                        is Array<*> -> {
                            val list = ArrayList<Float>()
                            for (item in value) {
                                val sub = flattenTensorValue(item)
                                for (v in sub) {
                                    list.add(v)
                                }
                            }
                            list.toFloatArray()
                        }
                        else -> floatArrayOf()
                    }
                }
            }
            else -> floatArrayOf()
        }
    }

    private fun buildImageTensor(bitmap: Bitmap, modelShape: LongArray): TensorData {
        val targetSize = if (imageInputSize > 0) imageInputSize else 224
        val cropped = centerCropSquare(bitmap)
        val resized = Bitmap.createScaledBitmap(cropped, targetSize, targetSize, true)
        if (cropped !== bitmap) {
            cropped.recycle()
        }

        val shape = modelShape.copyOf()
        if (shape.size != 4) {
            throw IllegalStateException("Expected vision input rank 4, got ${shape.size}.")
        }

        val n = if (shape[0] <= 0) 1 else shape[0].toInt()
        val h: Int
        val w: Int
        val channelsLast: Boolean
        if (shape[1] == 3L) {
            channelsLast = false
            h = if (shape[2] <= 0) targetSize else shape[2].toInt()
            w = if (shape[3] <= 0) targetSize else shape[3].toInt()
        } else if (shape[3] == 3L) {
            channelsLast = true
            h = if (shape[1] <= 0) targetSize else shape[1].toInt()
            w = if (shape[2] <= 0) targetSize else shape[2].toInt()
        } else {
            channelsLast = false
            h = targetSize
            w = targetSize
            shape[1] = 3
            shape[2] = h.toLong()
            shape[3] = w.toLong()
        }

        val resizedForInput = if (resized.width == w && resized.height == h) {
            resized
        } else {
            Bitmap.createScaledBitmap(resized, w, h, true)
        }
        if (resizedForInput !== resized) {
            resized.recycle()
        }

        val pixels = IntArray(w * h)
        resizedForInput.getPixels(pixels, 0, w, 0, 0, w, h)
        resizedForInput.recycle()

        val batch = max(1, n)
        val data = FloatArray(batch * 3 * h * w)

        var pixelIndex = 0
        for (y in 0 until h) {
            for (x in 0 until w) {
                val color = pixels[pixelIndex]
                val r = ((color shr 16) and 0xff) / 255.0f
                val g = ((color shr 8) and 0xff) / 255.0f
                val b = (color and 0xff) / 255.0f

                val nr = (r - imageMean[0]) / imageStd[0]
                val ng = (g - imageMean[1]) / imageStd[1]
                val nb = (b - imageMean[2]) / imageStd[2]

                if (channelsLast) {
                    val base = (y * w + x) * 3
                    data[base] = nr
                    data[base + 1] = ng
                    data[base + 2] = nb
                } else {
                    val hw = h * w
                    val offset = y * w + x
                    data[offset] = nr
                    data[hw + offset] = ng
                    data[(2 * hw) + offset] = nb
                }

                pixelIndex++
            }
        }

        return TensorData(
            shape = longArrayOf(
                1L,
                if (channelsLast) h.toLong() else 3L,
                if (channelsLast) w.toLong() else h.toLong(),
                if (channelsLast) 3L else w.toLong(),
            ),
            data = data,
        )
    }

    private fun centerCropSquare(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        if (width == height) {
            return bitmap.copy(bitmap.config ?: Bitmap.Config.ARGB_8888, false)
        }

        val size = min(width, height)
        val left = ((width - size) / 2).coerceAtLeast(0)
        val top = ((height - size) / 2).coerceAtLeast(0)
        return Bitmap.createBitmap(bitmap, left, top, size, size)
    }

    private fun resizeAndNormalize(vector: FloatArray, requestedDimensions: Int): List<Double> {
        val target = if (requestedDimensions > 0) requestedDimensions else vector.size
        val resized = if (target == vector.size) {
            vector
        } else {
            resampleVector(vector, target)
        }

        var magnitude = 0.0
        for (value in resized) {
            magnitude += value * value
        }
        magnitude = sqrt(magnitude)
        if (magnitude <= 1e-9) {
            return resized.map { it.toDouble() }
        }

        return resized.map { (it / magnitude).toDouble() }
    }

    private fun resampleVector(source: FloatArray, targetDimensions: Int): FloatArray {
        val safeTarget = max(1, targetDimensions)
        if (source.isEmpty()) {
            return FloatArray(safeTarget)
        }
        if (source.size == safeTarget) {
            return source
        }

        val result = FloatArray(safeTarget)
        val scale = source.size.toDouble() / safeTarget
        for (i in 0 until safeTarget) {
            val start = i * scale
            val end = (i + 1) * scale
            val left = start.toInt().coerceIn(0, source.size - 1)
            val right = max(left, min(source.size - 1, end.roundToInt() - 1))
            var sum = 0.0f
            var count = 0
            for (index in left..right) {
                sum += source[index]
                count += 1
            }
            result[i] = if (count <= 0) source[left] else sum / count
        }
        return result
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

    data class EngineManifest(
        val runtimeName: String,
        val quantized: Boolean,
        val dimensions: Int,
        val contextLength: Int,
        val textModelAsset: String,
        val visionModelAsset: String,
        val vocabAsset: String,
        val mergesAsset: String,
        val imageInputSize: Int,
        val imageMean: FloatArray,
        val imageStd: FloatArray,
    )

    data class TensorData(
        val shape: LongArray,
        val data: FloatArray,
    )
}

private fun JSONArray.toFloatArray(expectedSize: Int): FloatArray {
    val size = if (length() > 0) length() else expectedSize
    val result = FloatArray(size)
    for (index in 0 until size) {
        result[index] = optDouble(index, 0.0).toFloat()
    }
    if (result.size == expectedSize) {
        return result
    }

    val normalized = FloatArray(expectedSize)
    for (index in 0 until expectedSize) {
        normalized[index] = if (index < result.size) result[index] else result.lastOrNull() ?: 0f
    }
    return normalized
}

private class ClipBPETokenizer(
    vocab: Map<String, Int>,
    merges: List<Pair<String, String>>,
    private val contextLength: Int,
) {
    private val vocab = vocab
    private val bpeRanks: Map<Pair<String, String>, Int> = merges.withIndex().associate {
        it.value to it.index
    }
    private val cache = ConcurrentHashMap<String, List<String>>()

    private val startTokenId: Int = vocab["<|startoftext|>"]
        ?: throw IllegalStateException("Tokenizer vocabulary missing <|startoftext|>")
    private val endTokenId: Int = vocab["<|endoftext|>"]
        ?: throw IllegalStateException("Tokenizer vocabulary missing <|endoftext|>")

    private val byteEncoder: Map<Int, String> = buildByteEncoder()

    private val tokenRegex = Regex(
        "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+",
    )

    fun encode(text: String): LongArray {
        val ids = ArrayList<Int>(contextLength)
        ids.add(startTokenId)

        val matches = tokenRegex.findAll(text.lowercase())
        for (match in matches) {
            val token = match.value
            val encoded = encodeToByteUnicode(token)
            val bpeTokens = bpe(encoded)
            for (piece in bpeTokens) {
                val id = vocab[piece] ?: endTokenId
                ids.add(id)
                if (ids.size >= contextLength - 1) {
                    break
                }
            }
            if (ids.size >= contextLength - 1) {
                break
            }
        }

        ids.add(endTokenId)
        if (ids.size > contextLength) {
            ids.subList(contextLength, ids.size).clear()
            ids[contextLength - 1] = endTokenId
        }
        while (ids.size < contextLength) {
            ids.add(endTokenId)
        }

        return ids.map { it.toLong() }.toLongArray()
    }

    private fun encodeToByteUnicode(token: String): String {
        val bytes = token.toByteArray(Charsets.UTF_8)
        val builder = StringBuilder(bytes.size * 2)
        for (value in bytes) {
            val normalized = value.toInt() and 0xff
            builder.append(byteEncoder[normalized] ?: "")
        }
        return builder.toString()
    }

    private fun bpe(token: String): List<String> {
        cache[token]?.let { return it }

        if (token.isEmpty()) {
            return listOf("</w>")
        }

        var word = token.map { it.toString() }.toMutableList()
        val last = word.lastIndex
        word[last] = "${word[last]}</w>"

        var pairs = getPairs(word)
        while (pairs.isNotEmpty()) {
            var bestPair: Pair<String, String>? = null
            var bestRank = Int.MAX_VALUE
            for (pair in pairs) {
                val rank = bpeRanks[pair] ?: continue
                if (rank < bestRank) {
                    bestRank = rank
                    bestPair = pair
                }
            }

            val selected = bestPair ?: break
            val first = selected.first
            val second = selected.second

            val merged = mutableListOf<String>()
            var index = 0
            while (index < word.size) {
                val current = word[index]
                if (index < word.size - 1 && current == first && word[index + 1] == second) {
                    merged.add("$first$second")
                    index += 2
                } else {
                    merged.add(current)
                    index += 1
                }
            }

            word = merged
            if (word.size == 1) {
                break
            }
            pairs = getPairs(word)
        }

        val result = word.toList()
        cache[token] = result
        return result
    }

    private fun getPairs(word: List<String>): Set<Pair<String, String>> {
        if (word.size < 2) return emptySet()
        val pairs = LinkedHashSet<Pair<String, String>>(word.size)
        var previous = word[0]
        for (index in 1 until word.size) {
            val current = word[index]
            pairs.add(previous to current)
            previous = current
        }
        return pairs
    }

    private fun buildByteEncoder(): Map<Int, String> {
        val bytes = mutableListOf<Int>()
        for (value in 33..126) bytes.add(value)
        for (value in 161..172) bytes.add(value)
        for (value in 174..255) bytes.add(value)

        val chars = bytes.toMutableList()
        val existing = bytes.toHashSet()
        var extra = 0
        for (value in 0..255) {
            if (existing.contains(value)) continue
            bytes.add(value)
            chars.add(256 + extra)
            extra += 1
        }

        val encoder = HashMap<Int, String>(bytes.size)
        for (index in bytes.indices) {
            encoder[bytes[index]] = chars[index].toChar().toString()
        }
        return encoder
    }
}
