class UrlValidationResult {
  final bool isValid;
  final Uri? uri;
  final String? error;

  const UrlValidationResult._({required this.isValid, this.uri, this.error});

  const UrlValidationResult.valid(Uri uri)
    : this._(isValid: true, uri: uri, error: null);

  const UrlValidationResult.invalid(String message)
    : this._(isValid: false, uri: null, error: message);
}

class UrlValidationService {
  static const Set<String> supportedSchemes = {'http', 'https', 'rtsp', 'rtmp'};

  static UrlValidationResult validateNetworkUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const UrlValidationResult.invalid('URL is required.');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return const UrlValidationResult.invalid('URL is malformed.');
    }

    if (!uri.hasScheme) {
      return const UrlValidationResult.invalid(
        'URL must include a supported scheme.',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (!supportedSchemes.contains(scheme)) {
      return UrlValidationResult.invalid(
        'Unsupported scheme "$scheme". Use http, https, rtsp, or rtmp.',
      );
    }

    final hasAuthority = uri.host.isNotEmpty;
    if (!hasAuthority) {
      return const UrlValidationResult.invalid('URL host is missing.');
    }

    return UrlValidationResult.valid(uri);
  }
}
