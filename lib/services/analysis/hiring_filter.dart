/// Cheap, offline hiring filter. Runs before any AI call so obvious
/// non-hiring posts never cost tokens. Thresholds are conservative: a post
/// that mentions hiring signals still needs a decision, not a rejection.
bool looksLikeHiringPost(String text, {int threshold = 4}) {
  final normalized = text.toLowerCase();
  if (normalized.trim().isEmpty) return false;

  var score = 0;
  void hit(bool condition, [int weight = 1]) {
    if (condition) score += weight;
  }

  hit(
    RegExp(r"\bwe are hiring\b|\bwe're hiring\b|\bwe’re hiring\b")
        .hasMatch(normalized),
    3,
  );
  hit(RegExp(r'\bhiring\b').hasMatch(normalized), 2);
  hit(
    RegExp(r'\bjob opening\b|\bopen role\b|\bopen position\b|\bopen roles\b')
        .hasMatch(normalized),
    2,
  );
  hit(RegExp(r'\bjoin (our|my|the) team\b').hasMatch(normalized), 2);
  hit(RegExp(r'\blooking for a\b|\blooking for an\b').hasMatch(normalized), 1);
  hit(
    RegExp(r'\bapply now\b|\bapply here\b|\bapply\b').hasMatch(normalized),
    1,
  );
  hit(
    RegExp(r'\bdm me\b|\bcomment .{0,12}interested\b|\bdrop a comment\b')
        .hasMatch(normalized),
    1,
  );
  hit(
    RegExp(r'\bvacancy\b|\bvacancies\b|\bjob alert\b').hasMatch(normalized),
    1,
  );

  return score >= threshold;
}
