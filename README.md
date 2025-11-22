# Empty Player

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

## Customization Ideas
- Integrate a streaming backend (e.g., HLS/DASH).
- Add playlists & queue management.
- Persist playback position with `shared_preferences`.
- Expand settings (brightness, orientation, quality selection).

## License
See `LICENSE` file for details.

---
Made with Flutter.
