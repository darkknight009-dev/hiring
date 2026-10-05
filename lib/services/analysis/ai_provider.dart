import '../../models/opportunity.dart';
import '../../models/outreach.dart';

/// What the AI provider returned for one captured post.
class AnalysisResult {
  const AnalysisResult({required this.analysis, required this.modelUsed});
  final PostAnalysis analysis;
  final String modelUsed;
}

/// Ready-made outreach material. The user reviews, copies, and sends it
/// manually — the app never sends anything on their behalf.
class UserProfile {
  const UserProfile({
    required this.name,
    required this.headline,
    required this.skills,
    required this.tone,
  });

  final String name;
  final String headline;
  final String skills;
  final String tone;

  bool get hasContent =>
      name.isNotEmpty || headline.isNotEmpty || skills.isNotEmpty;
}

/// The analysis pipeline consumes this contract, not a specific vendor SDK.
/// Implementations must throw [AiAnalysisException] on failure so the UI can
/// offer a retry and keep the user's input.
abstract class AiProvider {
  Future<AnalysisResult> analyzePost({required String text, Uri? url});

  /// [kind] is one of `connectionNote`, `dm`, `email`.
  Future<OutreachDraft> generateDraft({
    required String kind,
    required String postText,
    String? posterName,
    String? role,
    String? company,
    required UserProfile profile,
  });
}

class AiAnalysisException implements Exception {
  const AiAnalysisException(this.message);
  final String message;
  @override
  String toString() => message;
}
