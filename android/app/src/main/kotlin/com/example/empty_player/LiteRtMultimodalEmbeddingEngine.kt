package com.example.empty_player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONObject
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.Tensor
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

class LiteRtMultimodalEmbeddingEngine(
    private val context: Context,
) {
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

    private var textInterpreter: Interpreter? = null
    private var visionInterpreter: Interpreter? = null
    private var tokenizer: LiteRtClipBPETokenizer? = null

    data class RuntimeStatus(
        val ready: Boolean,
        val runtimeName: String,
        val provider: String,
        val quantized: Boolean,
        val dimensions: Int,
        val reason: String?,
    )

    fun runtimeStatus(): RuntimeStatus {
        ensureInitialized()
        val ready = textInterpreter != null && visionInterpreter != null && tokenizer != null
        return RuntimeStatus(
            ready = ready,
            runtimeName = runtimeName,
            provider = provider,
            quantized = quantized,
            dimensions = dimensions,
            reason = if (ready) null else (initError ?: "LiteRT runtime is not initialized."),
        )
    }

    fun embedText(query: String, requestedDimensions: Int): List<Double> {
        ensureReady()
        val localTokenizer = tokenizer ?: throw IllegalStateException("Tokenizer unavailable")
        val localInterpreter = textInterpreter ?: throw IllegalStateException("Text model unavailable")

        val tokenIds = localTokenizer.encode(query)
        val inputs = buildTextInputs(localInterpreter, tokenIds)
        val vector = runInterpreter(localInterpreter, inputs)
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
        val localInterpreter = visionInterpreter ?: throw IllegalStateException("Vision model unavailable")

        val inputTensor = localInterpreter.getInputTensor(0)
        val inputBuffer = buildVisionInputBuffer(bitmap, inputTensor)
        val vector = runInterpreter(localInterpreter, arrayOf(inputBuffer))
        return resizeAndNormalize(vector, requestedDimensions)
    }

    private fun ensureReady() {
        ensureInitialized()
        val ready = textInterpreter != null && visionInterpreter != null && tokenizer != null
        if (!ready) {
            throw IllegalStateException(initError ?: "LiteRT runtime is unavailable.")
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
            tokenizer = LiteRtClipBPETokenizer(
                vocab = vocab,
                merges = merges,
                contextLength = manifest.contextLength,
            )

            val textModelPath = copyAssetToCache(manifest.textModelAsset)
            val visionModelPath = copyAssetToCache(manifest.visionModelAsset)
            createInterpretersWithFallback(
                textModelPath = textModelPath,
                visionModelPath = visionModelPath,
            )
            initError = null
        } catch (error: Exception) {
            clearInterpreters()
            tokenizer = null
            provider = "none"
            runtimeName = "embedding_unavailable"
            dimensions = 0
            quantized = false
            initError = error.message ?: "Failed to initialize LiteRT embedding engine."
        }
    }

    private fun createInterpretersWithFallback(
        textModelPath: File,
        visionModelPath: File,
    ) {
        val failures = mutableListOf<String>()

        val nnapiOptions = createInterpreterOptions(enableNnapi = true)
        try {
            val nnapiText = Interpreter(textModelPath, nnapiOptions)
            val nnapiVision = Interpreter(visionModelPath, nnapiOptions)
            val localTokenizer = tokenizer ?: throw IllegalStateException("Tokenizer unavailable")
            warmup(nnapiText, nnapiVision, localTokenizer)
            textInterpreter = nnapiText
            visionInterpreter = nnapiVision
            provider = "litert_nnapi"
            return
        } catch (error: Exception) {
            clearInterpreters()
            failures.add("NNAPI: ${extractReadableError(error)}")
        }

        val cpuOptions = createInterpreterOptions(enableNnapi = false)
        try {
            val cpuText = Interpreter(textModelPath, cpuOptions)
            val cpuVision = Interpreter(visionModelPath, cpuOptions)
            val localTokenizer = tokenizer ?: throw IllegalStateException("Tokenizer unavailable")
            warmup(cpuText, cpuVision, localTokenizer)
            textInterpreter = cpuText
            visionInterpreter = cpuVision
            provider = "litert_cpu"
            return
        } catch (error: Exception) {
            clearInterpreters()
            failures.add("CPU: ${extractReadableError(error)}")
        }

        val freshTextPath = copyAssetToCache(
            textModelAsset ?: textModelPath.name,
            forceRewrite = true,
        )
        val freshVisionPath = copyAssetToCache(
            visionModelAsset ?: visionModelPath.name,
            forceRewrite = true,
        )

        try {
            val cpuText = Interpreter(freshTextPath, cpuOptions)
            val cpuVision = Interpreter(freshVisionPath, cpuOptions)
            val localTokenizer = tokenizer ?: throw IllegalStateException("Tokenizer unavailable")
            warmup(cpuText, cpuVision, localTokenizer)
            textInterpreter = cpuText
            visionInterpreter = cpuVision
            provider = "litert_cpu"
            return
        } catch (error: Exception) {
            clearInterpreters()
            failures.add("CPU (after recopy): ${extractReadableError(error)}")
        }

        val detail = failures.joinToString(" | ")
        throw IllegalStateException(
            if (detail.isBlank()) {
                "LiteRT runtime failed to initialize."
            } else {
                "LiteRT runtime failed to initialize. $detail"
            },
        )
    }

    private fun warmup(
        text: Interpreter,
        vision: Interpreter,
        localTokenizer: LiteRtClipBPETokenizer,
    ) {
        val tokenIds = localTokenizer.encode("warmup")
        val textInputs = buildTextInputs(text, tokenIds)
        runInterpreter(text, textInputs)

        val targetSize = max(1, imageInputSize)
        val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        try {
            val visionInput = buildVisionInputBuffer(bitmap, vision.getInputTensor(0))
            runInterpreter(vision, arrayOf(visionInput))
        } finally {
            bitmap.recycle()
        }
    }

    private fun createInterpreterOptions(enableNnapi: Boolean): Interpreter.Options {
        return Interpreter.Options().apply {
            setNumThreads(2)
            setUseNNAPI(enableNnapi)
        }
    }

    private fun clearInterpreters() {
        textInterpreter?.close()
        visionInterpreter?.close()
        textInterpreter = null
        visionInterpreter = null
    }

    private fun buildTextInputs(
        interpreter: Interpreter,
        tokenIds: LongArray,
    ): Array<Any> {
        val inputCount = interpreter.inputTensorCount
        val inputs = ArrayList<Any>(inputCount)
        for (index in 0 until inputCount) {
            val tensor = interpreter.getInputTensor(index)
            val tensorName = tensor.name().lowercase()
            val values = when {
                tensorName.contains("mask") -> LongArray(tokenIds.size) { 1L }
                tensorName.contains("token_type") || tensorName.contains("segment") -> {
                    LongArray(tokenIds.size)
                }
                tensorName.contains("position") -> LongArray(tokenIds.size) { it.toLong() }
                else -> tokenIds
            }
            inputs.add(buildSequenceInputBuffer(values, tensor))
        }
        return inputs.toTypedArray()
    }

    private fun buildSequenceInputBuffer(values: LongArray, tensor: Tensor): ByteBuffer {
        val shape = tensor.shape()
        val totalElements = shape.fold(1) { acc, dim ->
            val safeDim = if (dim <= 0) 1 else dim
            acc * safeDim
        }
        val dataType = tensor.dataType()
        val quant = tensor.quantizationParams()

        val buffer = ByteBuffer.allocateDirect(tensor.numBytes()).order(ByteOrder.nativeOrder())
        for (index in 0 until totalElements) {
            val value = if (index < values.size) values[index] else values.lastOrNull() ?: 0L
            when (dataType) {
                DataType.INT32 -> buffer.putInt(value.toInt())
                DataType.INT64 -> buffer.putLong(value)
                DataType.FLOAT32 -> buffer.putFloat(value.toFloat())
                DataType.UINT8 -> {
                    val quantized = quantizeToUInt8(
                        value = value.toFloat(),
                        scale = quant.scale,
                        zeroPoint = quant.zeroPoint,
                    )
                    buffer.put(quantized.toByte())
                }
                DataType.INT8 -> {
                    val quantized = quantizeToInt8(
                        value = value.toFloat(),
                        scale = quant.scale,
                        zeroPoint = quant.zeroPoint,
                    )
                    buffer.put(quantized.toByte())
                }
                else -> throw IllegalStateException("Unsupported text tensor input type: $dataType")
            }
        }
        buffer.rewind()
        return buffer
    }

    private fun buildVisionInputBuffer(bitmap: Bitmap, inputTensor: Tensor): ByteBuffer {
        val modelShape = inputTensor.shape()
        if (modelShape.size != 4) {
            throw IllegalStateException("Expected vision input rank 4, got ${modelShape.size}.")
        }

        val channelsLast = modelShape[3] == 3
        val channelsFirst = modelShape[1] == 3
        if (!channelsLast && !channelsFirst) {
            throw IllegalStateException("Unsupported vision input shape: ${modelShape.contentToString()}")
        }

        val targetHeight = if (channelsLast) {
            if (modelShape[1] > 0) modelShape[1] else imageInputSize
        } else {
            if (modelShape[2] > 0) modelShape[2] else imageInputSize
        }
        val targetWidth = if (channelsLast) {
            if (modelShape[2] > 0) modelShape[2] else imageInputSize
        } else {
            if (modelShape[3] > 0) modelShape[3] else imageInputSize
        }

        val cropped = centerCropSquare(bitmap)
        val resized = Bitmap.createScaledBitmap(cropped, targetWidth, targetHeight, true)
        if (cropped !== bitmap) {
            cropped.recycle()
        }

        val pixels = IntArray(targetWidth * targetHeight)
        resized.getPixels(pixels, 0, targetWidth, 0, 0, targetWidth, targetHeight)
        resized.recycle()

        val dataType = inputTensor.dataType()
        val quant = inputTensor.quantizationParams()
        val values = FloatArray(targetWidth * targetHeight * 3)

        var pixelIndex = 0
        for (y in 0 until targetHeight) {
            for (x in 0 until targetWidth) {
                val color = pixels[pixelIndex]
                val r = ((color shr 16) and 0xff) / 255.0f
                val g = ((color shr 8) and 0xff) / 255.0f
                val b = (color and 0xff) / 255.0f

                val nr = (r - imageMean[0]) / imageStd[0]
                val ng = (g - imageMean[1]) / imageStd[1]
                val nb = (b - imageMean[2]) / imageStd[2]

                if (channelsLast) {
                    val base = (y * targetWidth + x) * 3
                    values[base] = nr
                    values[base + 1] = ng
                    values[base + 2] = nb
                } else {
                    val hw = targetHeight * targetWidth
                    val offset = y * targetWidth + x
                    values[offset] = nr
                    values[hw + offset] = ng
                    values[(2 * hw) + offset] = nb
                }
                pixelIndex += 1
            }
        }

        val buffer = ByteBuffer.allocateDirect(inputTensor.numBytes()).order(ByteOrder.nativeOrder())
        for (value in values) {
            when (dataType) {
                DataType.FLOAT32 -> buffer.putFloat(value)
                DataType.UINT8 -> {
                    val quantized = quantizeToUInt8(
                        value = value,
                        scale = quant.scale,
                        zeroPoint = quant.zeroPoint,
                    )
                    buffer.put(quantized.toByte())
                }
                DataType.INT8 -> {
                    val quantized = quantizeToInt8(
                        value = value,
                        scale = quant.scale,
                        zeroPoint = quant.zeroPoint,
                    )
                    buffer.put(quantized.toByte())
                }
                else -> throw IllegalStateException("Unsupported vision input type: $dataType")
            }
        }
        buffer.rewind()
        return buffer
    }

    private fun runInterpreter(interpreter: Interpreter, inputs: Array<Any>): FloatArray {
        if (interpreter.outputTensorCount <= 0) {
            throw IllegalStateException("Model returned no output tensor.")
        }
        val outputTensor = interpreter.getOutputTensor(0)
        val outputBuffer = ByteBuffer
            .allocateDirect(outputTensor.numBytes())
            .order(ByteOrder.nativeOrder())
        val outputs = HashMap<Int, Any>(1)
        outputs[0] = outputBuffer

        interpreter.runForMultipleInputsOutputs(inputs, outputs)
        outputBuffer.rewind()

        val decoded = decodeOutputTensor(outputTensor, outputBuffer)
        if (decoded.isEmpty()) {
            throw IllegalStateException("Model returned an empty embedding vector.")
        }
        return selectLikelyEmbeddingSlice(outputTensor.shape(), decoded)
    }

    private fun decodeOutputTensor(
        tensor: Tensor,
        buffer: ByteBuffer,
    ): FloatArray {
        val elementCount = tensor.numElements()
        val dataType = tensor.dataType()
        val quant = tensor.quantizationParams()

        return when (dataType) {
            DataType.FLOAT32 -> {
                val result = FloatArray(elementCount)
                for (index in 0 until elementCount) {
                    result[index] = buffer.float
                }
                result
            }
            DataType.INT32 -> {
                val result = FloatArray(elementCount)
                for (index in 0 until elementCount) {
                    result[index] = buffer.int.toFloat()
                }
                result
            }
            DataType.INT64 -> {
                val result = FloatArray(elementCount)
                for (index in 0 until elementCount) {
                    result[index] = buffer.long.toFloat()
                }
                result
            }
            DataType.UINT8 -> {
                val result = FloatArray(elementCount)
                val scale = if (quant.scale == 0f) 1f else quant.scale
                val zeroPoint = quant.zeroPoint
                for (index in 0 until elementCount) {
                    val raw = buffer.get().toInt() and 0xff
                    result[index] = (raw - zeroPoint) * scale
                }
                result
            }
            DataType.INT8 -> {
                val result = FloatArray(elementCount)
                val scale = if (quant.scale == 0f) 1f else quant.scale
                val zeroPoint = quant.zeroPoint
                for (index in 0 until elementCount) {
                    val raw = buffer.get().toInt()
                    result[index] = (raw - zeroPoint) * scale
                }
                result
            }
            DataType.INT16 -> {
                val result = FloatArray(elementCount)
                for (index in 0 until elementCount) {
                    result[index] = buffer.short.toFloat()
                }
                result
            }
            else -> throw IllegalStateException("Unsupported model output type: $dataType")
        }
    }

    private fun selectLikelyEmbeddingSlice(shape: IntArray, flattened: FloatArray): FloatArray {
        if (shape.isEmpty()) {
            return flattened
        }
        val lastDim = shape.last()
        if (lastDim <= 0 || flattened.size <= lastDim) {
            return flattened
        }

        return flattened.copyOfRange(0, lastDim)
    }

    private fun quantizeToUInt8(value: Float, scale: Float, zeroPoint: Int): Int {
        val safeScale = if (scale == 0f) 1f else scale
        val quantized = (value / safeScale + zeroPoint).roundToInt()
        return quantized.coerceIn(0, 255)
    }

    private fun quantizeToInt8(value: Float, scale: Float, zeroPoint: Int): Int {
        val safeScale = if (scale == 0f) 1f else scale
        val quantized = (value / safeScale + zeroPoint).roundToInt()
        return quantized.coerceIn(-128, 127)
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

        val runtimeName = json.optString("runtimeName", "mobileclip_litert")
        val quantized = json.optBoolean("quantized", true)
        val dimensions = json.optInt("dimensions", 512)
        val contextLength = json.optInt("contextLength", 77)

        val textModelAsset = json.optString("textModelAsset").trim()
        val visionModelAsset = json.optString("visionModelAsset").trim()
        if (textModelAsset.isEmpty() || visionModelAsset.isEmpty()) {
            throw IllegalStateException("Manifest is missing model asset paths.")
        }
        if (!textModelAsset.lowercase().endsWith(".tflite") ||
            !visionModelAsset.lowercase().endsWith(".tflite")
        ) {
            throw IllegalStateException(
                "LiteRT backend requires .tflite text and vision model assets in embedding manifest.",
            )
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
        val mean = imageJson?.optJSONArray("mean")?.toLiteRtFloatArray(3)
            ?: floatArrayOf(0.48145466f, 0.4578275f, 0.40821073f)
        val std = imageJson?.optJSONArray("std")?.toLiteRtFloatArray(3)
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

    private fun extractReadableError(error: Throwable): String {
        val raw = (error.message ?: error.toString()).trim()
        if (raw.isEmpty()) return "unknown error"
        return raw
            .replace('\n', ' ')
            .replace(Regex("\\s+"), " ")
            .take(280)
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
}

private fun JSONArray.toLiteRtFloatArray(expectedSize: Int): FloatArray {
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

private class LiteRtClipBPETokenizer(
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
