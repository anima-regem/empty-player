#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/assets/models/clip"
mkdir -p "$OUT_DIR"

BASE_URL="https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/main"

fetch() {
  local remote_path="$1"
  local output_name="$2"
  local output_path="$OUT_DIR/$output_name"
  echo "Downloading $remote_path -> $output_path"
  curl -L --fail --retry 3 --retry-delay 2 \
    "$BASE_URL/$remote_path" \
    -o "$output_path"
}

fetch "onnx/text_model_int8.onnx" "text_model_int8.onnx"
fetch "onnx/vision_model_int8.onnx" "vision_model_int8.onnx"
fetch "vocab.json" "vocab.json"
fetch "merges.txt" "merges.txt"

# Optional references
fetch "tokenizer.json" "tokenizer.json"
fetch "preprocessor_config.json" "preprocessor_config.json"

# Optional fp32 fallback models for devices where int8 ops are not implemented.
if [[ "${INCLUDE_FP32:-0}" == "1" ]]; then
  fetch "onnx/text_model.onnx" "text_model.onnx"
  fetch "onnx/vision_model.onnx" "vision_model.onnx"
fi

echo "Done. Assets are in $OUT_DIR"
