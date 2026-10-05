/// Raw, user-provided input. This is not an analyzed opportunity.
class CapturedPost {
  const CapturedPost._({required this.text, required this.url});

  static const maxTextLength = 20000;
  static const maxUrlLength = 2048;

  final String? text;
  final Uri? url;

  factory CapturedPost.fromInput({String text = '', String url = ''}) {
    final normalizedText = text.trim();
    final normalizedUrl = url.trim();
    if (normalizedText.isEmpty && normalizedUrl.isEmpty) {
      throw const FormatException(
        'Paste a LinkedIn post URL or some post text to continue.',
      );
    }
    final urlError = validateUrl(normalizedUrl);
    final textError = validateText(normalizedText);
    if (urlError != null || textError != null) {
      throw FormatException(urlError ?? textError!);
    }
    return CapturedPost._(
      text: normalizedText.isEmpty ? null : normalizedText,
      url: normalizedUrl.isEmpty ? null : Uri.parse(normalizedUrl),
    );
  }

  static String? validateText(String? value) {
    if ((value?.trim().length ?? 0) > maxTextLength) {
      return 'Keep post content to $maxTextLength characters or fewer.';
    }
    return null;
  }

  static String? validateUrl(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return null;
    if (input.length > maxUrlLength) return 'This URL is too long.';
    final uri = Uri.tryParse(input);
    final host = uri?.host ?? '';
    final isLinkedInHost =
        host == 'linkedin.com' ||
        host.endsWith('.linkedin.com') ||
        host == 'lnkd.in' ||
        host.endsWith('.lnkd.in');
    if (uri == null ||
        uri.scheme != 'https' ||
        !isLinkedInHost ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        RegExp(r'\s').hasMatch(input)) {
      return 'Use a valid HTTPS LinkedIn post URL (https://www.linkedin.com/…).';
    }
    // Share-friendly short links (lnkd.in/<code>) carry an opaque path, not a
    // /posts/ segment. Accept them as-is; post-path rules do not apply.
    if (host == 'lnkd.in' || host.endsWith('.lnkd.in')) return null;
    if (!(uri.path.startsWith('/posts/') ||
            uri.path.startsWith('/feed/update/') ||
            uri.path.startsWith('/pulse/')) ||
        uri.pathSegments.last.isEmpty) {
      return 'Use a LinkedIn post link, not a profile or homepage.';
    }
    return null;
  }
}
