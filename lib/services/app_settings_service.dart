import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  static const _keyBackgroundPlayback = 'background_playback_enabled';
  static const _keyPipOnClose = 'pip_on_close_enabled';
  static const _keyDefaultSpeed = 'default_playback_speed';
  static const _keyLoadingAnimationType = 'loading_animation_type';

  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  bool get backgroundPlaybackEnabled => _prefs?.getBool(_keyBackgroundPlayback) ?? false;
  set backgroundPlaybackEnabled(bool value) => _prefs?.setBool(_keyBackgroundPlayback, value);

  bool get pipOnCloseEnabled => _prefs?.getBool(_keyPipOnClose) ?? true;
  set pipOnCloseEnabled(bool value) => _prefs?.setBool(_keyPipOnClose, value);

  double get defaultPlaybackSpeed => _prefs?.getDouble(_keyDefaultSpeed) ?? 1.0;
  set defaultPlaybackSpeed(double value) => _prefs?.setDouble(_keyDefaultSpeed, value);

  // Loading animation type: 'pulsating' or 'rive'
  String get loadingAnimationType => _prefs?.getString(_keyLoadingAnimationType) ?? 'pulsating';
  set loadingAnimationType(String value) => _prefs?.setString(_keyLoadingAnimationType, value);
}
