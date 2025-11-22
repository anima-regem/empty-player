import 'dart:convert';
import 'package:http/http.dart' as http;

class UpdateCheckService {
  static const String _owner = 'anima-regem';
  static const String _repo = 'empty-player';
  static const String _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Fetches the latest release information from GitHub
  /// Returns a map with 'tag_name', 'name', 'body', 'html_url', 'published_at'
  /// Returns null if unable to fetch or parse the data
  Future<Map<String, dynamic>?> fetchLatestRelease() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return {
          'tag_name': data['tag_name'] as String?,
          'name': data['name'] as String?,
          'body': data['body'] as String?,
          'html_url': data['html_url'] as String?,
          'published_at': data['published_at'] as String?,
        };
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching latest release: $e');
      return null;
    }
  }

  /// Compares two version strings (e.g., "1.0.0" and "0.3.0")
  /// Returns true if newVersion is greater than currentVersion
  /// Assumes semantic versioning format: v?major.minor.patch
  bool isNewerVersion(String currentVersion, String newVersion) {
    // Remove 'v' prefix if present
    final current = currentVersion.replaceFirst(RegExp(r'^v'), '');
    final latest = newVersion.replaceFirst(RegExp(r'^v'), '');

    final currentParts = current
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final latestParts = latest
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    // Ensure both have at least 3 parts (major.minor.patch)
    while (currentParts.length < 3) {
      currentParts.add(0);
    }
    while (latestParts.length < 3) {
      latestParts.add(0);
    }

    // Compare major, minor, patch
    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) {
        return true;
      } else if (latestParts[i] < currentParts[i]) {
        return false;
      }
    }

    return false; // Versions are equal
  }
}
