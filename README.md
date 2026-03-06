# Empty Player

![Build](https://github.com/anima-regem/empty-player/workflows/Build%20and%20Test/badge.svg)
![Release](https://github.com/anima-regem/empty-player/workflows/Release/badge.svg)

Android-focused Flutter video player with local library browsing, mini-player/PiP playback, and on-device semantic + visual search.

## Highlights
- Local device video scan with cache-aware refresh and runtime permission handling.
- Folder-first library UI with pinning, favorites, and continue-watching state.
- Local/network/content URI playback via `media_kit`.
- Mini player handoff between list and full player pages.
- Picture-in-Picture (PiP) support and playback transport service hooks.
- Subtitle support (`.srt`/`.vtt`) with calibration offset controls.
- On-device embedding runtime selection in Settings (`Auto`, `Android native`, `Deterministic fallback`).
- Text and image search over indexed video frames with ANN-style vector retrieval + reranking.
- Runtime health, indexing progress, and release update checks surfaced in-app.

## Architecture Snapshot
```text
lib/
  main.dart                          # Bootstraps V2 data layer, launches app
  ui/video_frame.dart                # App shell + Android intent bridge
  pages/
    home_page.dart                   # Library, search, indexing orchestration
    video_player.dart                # Fullscreen player UX + subtitle controls
    settings_page.dart               # Runtime mode, indexing status, updates
  services/
    video_semantic_search_service.dart
    embedding_runtime.dart
    vector_index_repository.dart
    mini_player_service.dart
  v2/
    app_shell/bootstrap_v2.dart      # DB init + migration wiring
    storage/                         # SQLite schema + repository impls
android/
  app/src/main/kotlin/...            # ONNX + LiteRT embedding engines
assets/models/
  embedding_manifest.json            # Runtime/model routing config
  clip/                              # ONNX model assets
  mobileclip/                        # LiteRT model assets
```

## Getting Started
1. Install Flutter (stable) and Android toolchain.
2. Verify environment:
   ```bash
   flutter doctor
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## Model Assets and Runtime Backends
The app reads `assets/models/embedding_manifest.json` to decide which Android embedding backend to use:
- `backend: "onnx"` or `.onnx` model assets -> ONNX Runtime backend
- `backend: "litert"` or `.tflite` model assets -> TensorFlow Lite (LiteRT) backend
- `backend: "auto"` -> backend inferred from configured model asset extensions

Useful references:
- `assets/models/clip/README.md` (ONNX assets)
- `assets/models/mobileclip/README.md` (LiteRT assets)

Refresh CLIP int8 assets:
```bash
./scripts/fetch_clip_int8_assets.sh
```

Optionally include fp32 fallback models:
```bash
INCLUDE_FP32=1 ./scripts/fetch_clip_int8_assets.sh
```

## Development Commands
```bash
flutter analyze
flutter test
flutter build apk --release
```

## CI/CD
- `Build and Test`: runs on pushes/PRs to `main` and `develop`.
- `PR Checks`: formatting, analysis, tests, and package dry-run on pull requests.
- `Release`: builds APK + AAB and publishes GitHub Releases when a `v*.*.*` tag is pushed.

Create a release tag:
```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

See `.github/CI_CD_GUIDE.md` and `.github/RELEASE_CAMPAIGN_PLAN.md` for full pipeline details.

## Download
Latest builds are published on the [Releases page](../../releases).

## License
See `LICENSE`.
