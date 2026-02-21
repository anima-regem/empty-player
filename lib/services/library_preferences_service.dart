import 'package:shared_preferences/shared_preferences.dart';

enum LibrarySortOption {
  nameAsc,
  nameDesc,
  dateModifiedDesc,
  sizeDesc,
  durationDesc,
}

class LibraryPreferencesService {
  static const _keyPinnedFolders = 'library_pinned_folders';
  static const _keySortOption = 'library_sort_option';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<Set<String>> getPinnedFolders() async {
    await init();
    return (_prefs?.getStringList(_keyPinnedFolders) ?? const <String>[])
        .toSet();
  }

  Future<void> setPinnedFolders(Set<String> values) async {
    await init();
    await _prefs?.setStringList(_keyPinnedFolders, values.toList()..sort());
  }

  Future<void> togglePinnedFolder(String folderPath) async {
    final pinned = await getPinnedFolders();
    if (pinned.contains(folderPath)) {
      pinned.remove(folderPath);
    } else {
      pinned.add(folderPath);
    }
    await setPinnedFolders(pinned);
  }

  Future<LibrarySortOption> getSortOption() async {
    await init();
    final raw = _prefs?.getString(_keySortOption);
    return LibrarySortOption.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => LibrarySortOption.nameAsc,
    );
  }

  Future<void> setSortOption(LibrarySortOption option) async {
    await init();
    await _prefs?.setString(_keySortOption, option.name);
  }
}
