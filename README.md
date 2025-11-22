# Empty Player

![Build](https://github.com/anima-regem/empty-player/workflows/Build%20and%20Test/badge.svg)
![Release](https://github.com/anima-regem/empty-player/workflows/Release/badge.svg)

Simple Flutter video/audio player scaffold with a mini player component and basic navigation pages. Useful as a starter for building a richer media experience.

## Features
- Mini player overlay (`components/mini_player.dart`) with service-driven state (`services/mini_player_service.dart`).
- Fun loading animations (`components/loading_animation.dart`) with pulsating and rotating effects.
- Video list and playback (`pages/video_list_page.dart`, `pages/video_player.dart`).
- Network stream demo (`pages/network_stream_page.dart`).
- Basic settings + about pages.
- Lightweight models (`models/video_item.dart`).

## Project Structure (key parts)
```
lib/
	main.dart                # App entry, routing
	frame.dart               # Common layout frame
	components/
		mini_player.dart         # Mini player component
		loading_animation.dart   # Fun loading animations
	models/video_item.dart
	pages/
		home_page.dart
		video_list_page.dart
		video_player.dart
		network_stream_page.dart
		settings_page.dart
		about_page.dart
	services/
		video_service.dart
		mini_player_service.dart
		app_settings_service.dart
	ui/video_frame.dart
assets/                    # Place static media assets here
```

## Getting Started
1. Ensure Flutter SDK is installed and on PATH.
2. Fetch dependencies:
	 ```bash
	 flutter pub get
	 ```
3. Run the app:
	 ```bash
	 flutter run
	 ```

## CI/CD Pipeline

This project uses GitHub Actions for automated building and releasing:

### Automated Builds
- **Build workflow** runs on every push and pull request to main/develop branches
- Performs code quality checks (formatting, analysis, tests)
- Generates APK artifacts for testing
- View workflow status in the [Actions tab](../../actions)

### Automated Releases
- **Release workflow** triggers when a version tag is pushed (e.g., `v1.0.0`)
- Builds both APK and AAB (App Bundle) files
- Creates GitHub Release with automated release notes
- Attaches downloadable artifacts

**To create a release:**
```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

See [Release Campaign Plan](.github/RELEASE_CAMPAIGN_PLAN.md) for detailed CI/CD documentation.

## Download

Download the latest release APK from the [Releases page](../../releases).

## Customization Ideas
- Integrate a streaming backend (e.g., HLS/DASH).
- Add playlists & queue management.
- Persist playback position with `shared_preferences`.
- Expand settings (brightness, orientation, quality selection).

## License
See `LICENSE` file for details.

---
Made with Flutter.
