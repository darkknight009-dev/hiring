import '../../models/captured_post.dart';

/// Shared parsing for content received from share targets.
/// Extra keys mirror the PWA share-target params: title, text, url.
CapturedPost? parseSharedExtras(Map<String, Object?>? extras) {
  if (extras == null || extras.isEmpty) return null;
  final title = (extras['title'] as String?)?.trim() ?? '';
  final text = (extras['text'] as String?)?.trim() ?? '';
  var url = (extras['url'] as String?)?.trim() ?? '';
  // Some apps put the link in the title field.
  if (url.isEmpty && title.startsWith('http')) url = title;
  final body = text.isNotEmpty ? text : (title.startsWith('http') ? '' : title);
  if (body.isEmpty && url.isEmpty) return null;
  try {
    return CapturedPost.fromInput(text: body, url: url);
  } on FormatException {
    // Content that fails URL validation (non-LinkedIn links) is still
    // useful as plain text.
    if (body.isNotEmpty) return CapturedPost.fromInput(text: body);
    return null;
  }
}
