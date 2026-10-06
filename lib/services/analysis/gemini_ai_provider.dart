import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/opportunity.dart';
import '../../models/outreach.dart';
import 'ai_provider.dart';

/// Calls the Gemini API directly from the device. The API key is supplied by
/// the user at runtime and stored locally; it is never compiled into the app.
class GeminiAiProvider implements AiProvider {
  GeminiAiProvider({
    required this.apiKey,
    this.model = defaultModel,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const defaultModel = 'gemini-2.0-flash';
  static const endpointHost = 'generativelanguage.googleapis.com';
  String get endpointPath => '/v1beta/models/$model:generateContent';

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _analysisInstruction =
      'You extract structured facts from LinkedIn-style posts for a personal '
      'job-opportunity inbox. Reply with ONLY a JSON object, no markdown, no '
      'commentary, with exactly these keys: '
      '"isHiring" ("true" or "false" — true only if the post offers or seeks '
      'a candidate for a job, internship, or freelance engagement), '
      '"confidence" (integer 0-100, your certainty in isHiring), '
      '"role" (job title or null), "company" (hiring company or null), '
      '"location" (or null), "applyInstructions" (how to apply, or null), '
      '"summary" (one sentence). Use JSON null for unknown fields. Never '
      'invent values that are not in the post.';

  @override
  Future<AnalysisResult> analyzePost({required String text, Uri? url}) async {
    final prompt = [
      if (url != null) 'Post URL: $url',
      if (text.isNotEmpty) 'Post text:\n$text',
    ].join('\n\n');
    if (prompt.isEmpty) {
      throw const AiAnalysisException('Nothing to analyze: the post is empty.');
    }
    final parsed = await _generateJson(
      prompt: prompt,
      systemInstruction: _analysisInstruction,
      maxOutputTokens: 512,
    );
    return AnalysisResult(
      analysis: PostAnalysis.fromJson(parsed),
      modelUsed: model,
    );
  }

  @override
  Future<OutreachDraft> generateDraft({
    required String kind,
    required String postText,
    String? posterName,
    String? role,
    String? company,
    required UserProfile profile,
  }) async {
    final kindRules = switch (kind) {
      'connectionNote' =>
        'Write a LinkedIn connection invitation note of AT MOST 200 characters. '
            'Its only goals: reference the specific role in their post, make the '
            'sender memorable, invite the connection. Do not ask for a job in the note.',
      'dm' =>
        'Write a LinkedIn direct message of AT MOST 500 characters for a person '
            'who is now connected. Reference the specific post and role, show fit '
            'in one line from the profile facts, say the resume is ready to share, '
            'and end with one clear question.',
      'email' =>
        'Write a job application email. Return {"subject": ..., "body": ...}. '
            'The subject is at most 70 characters and names the role. The body is '
            '150-250 words: greet the poster by name, reference the exact post, '
            'show fit in two short paragraphs using only the profile facts, mention '
            'the attached resume, and end with availability and a polite close '
            'signed with the sender name.',
      _ => throw const AiAnalysisException('Unknown draft type.'),
    };

    final prompt = [
      'Hiring post (verbatim):\n"""$postText"""',
      if (posterName != null && posterName.isNotEmpty)
        'Poster name: $posterName',
      if (role != null && role.isNotEmpty) 'Detected role: $role',
      if (company != null && company.isNotEmpty) 'Detected company: $company',
      'Sender profile facts (never invent anything beyond these):',
      'Name: ${profile.name.isEmpty ? "(unknown, use a neutral sign-off)" : profile.name}',
      if (profile.headline.isNotEmpty) 'Headline: ${profile.headline}',
      if (profile.skills.isNotEmpty) 'Skills and experience: ${profile.skills}',
      'Tone: ${profile.tone}. No emojis. No placeholders like [Company] — use the '
          'real names from the post, or omit the sentence.',
      'Rules: $kindRules',
      'Reply with ONLY a JSON object: {"subject": string or null, "body": string}.',
    ].join('\n\n');

    final parsed = await _generateJson(
      prompt: prompt,
      systemInstruction:
          'You write concise, specific outreach drafts for a job seeker based '
          'only on facts provided. Never fabricate experience, names, or companies.',
      maxOutputTokens: 700,
    );
    final body = (parsed['body'] as String?)?.trim() ?? '';
    if (body.isEmpty) {
      throw const AiAnalysisException('AI returned an empty draft. Try again.');
    }
    return OutreachDraft(
      kind: kind,
      subject: (parsed['subject'] as String?)?.trim(),
      body: body,
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<Map<String, dynamic>> _generateJson({
    required String prompt,
    required String systemInstruction,
    required int maxOutputTokens,
  }) async {
    // The key travels in a header, never in the URL query string, so it
    // cannot leak through proxy or request logs.
    final uri = Uri.https(endpointHost, endpointPath);
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': systemInstruction},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'temperature': 0.4,
                'maxOutputTokens': maxOutputTokens,
              },
            }),
          )
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const AiAnalysisException(
        'The AI request timed out. Check your connection and try again.',
      );
    } catch (_) {
      throw const AiAnalysisException(
        'Could not reach the AI provider. Check your connection and try again.',
      );
    }

    if (response.statusCode == 400 || response.statusCode == 403) {
      throw const AiAnalysisException(
        'The AI provider rejected the request. Check your API key in Settings.',
      );
    }
    if (response.statusCode == 429) {
      throw const AiAnalysisException(
        'AI rate limit or quota reached. Wait a moment and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw AiAnalysisException(
        'AI provider error (HTTP ${response.statusCode}). Try again later.',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AiAnalysisException(
        'AI returned a response that could not be read.',
      );
    }

    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiAnalysisException('AI returned no answer. Try again.');
    }
    final content = (candidates.first as Map)['content'];
    final parts = content is Map ? content['parts'] : null;
    final textOut = parts is List && parts.isNotEmpty
        ? (parts.first as Map)['text']
        : null;
    if (textOut is! String || textOut.isEmpty) {
      throw const AiAnalysisException(
        'AI returned an empty answer. Try again.',
      );
    }

    try {
      return jsonDecode(textOut) as Map<String, dynamic>;
    } catch (_) {
      throw const AiAnalysisException(
        'AI returned an answer that could not be parsed. Try again.',
      );
    }
  }

  void dispose() => _client.close();
}
