# MobileCLIP LiteRT Assets

To run the Android LiteRT backend, place the following files in this folder:

- `text_model_int8.tflite`
- `vision_model_int8.tflite`
- `vocab.json`
- `merges.txt`

Then update `/Users/vichukartha/Projects/empty_player/assets/models/embedding_manifest.json`:

```json
{
  "backend": "litert",
  "runtimeName": "mobileclip_litert_int8",
  "quantized": true,
  "dimensions": 512,
  "contextLength": 77,
  "textModelAsset": "assets/models/mobileclip/text_model_int8.tflite",
  "visionModelAsset": "assets/models/mobileclip/vision_model_int8.tflite",
  "tokenizer": {
    "vocabAsset": "assets/models/mobileclip/vocab.json",
    "mergesAsset": "assets/models/mobileclip/merges.txt"
  },
  "image": {
    "inputSize": 224,
    "mean": [0.48145466, 0.4578275, 0.40821073],
    "std": [0.26862954, 0.26130258, 0.27577711]
  }
}
```

The runtime selector automatically switches to LiteRT when `backend` is `litert`.
