import 'package:flutter/foundation.dart';

import 'captured_post.dart';
import 'opportunity.dart';
import 'outreach.dart';

/// A saved opportunity: the raw captured post plus its analysis, status,
/// outreach drafts, and manual connection tracking.
@immutable
class Opportunity {
  const Opportunity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.analysis,
    this.text,
    this.url,
    this.capturedVia = 'manual',
    this.connectionState = 'none',
    this.drafts = const {},
  });

  /// Statuses are explicit; the user moves an opportunity through them.
  static const statuses = [
    'new',
    'need-action',
    'applied',
    'follow-up',
    'archived',
  ];

  /// Manual connection tracking. The app never connects on the user's behalf.
  static const connectionStates = ['none', 'requested', 'accepted'];

  /// Where the post came from.
  static const capturedVias = ['manual', 'share', 'radar'];

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;
  final PostAnalysis analysis;
  final String? text;
  final Uri? url;
  final String capturedVia;

  /// `none` → not connected; `requested` → invite sent, awaiting accept;
  /// `accepted` → connected, DM unlocked.
  final String connectionState;

  /// Keyed by draft kind: connectionNote, dm, email.
  final Map<String, OutreachDraft> drafts;

  bool get isHiring => analysis.isHiring;

  OutreachScenario get scenario =>
      OutreachScenario.detect(analysis.applyInstructions ?? text ?? '');

  bool get dmUnlocked =>
      connectionState == 'accepted' || connectionState == 'requested';

  String get displayTitle {
    final role = analysis.role;
    final company = analysis.company;
    if (role != null && company != null) return '$role at $company';
    if (role != null) return role;
    if (company != null) return company;
    if (text != null) {
      final firstLine = text!.trim().split('\n').first;
      if (firstLine.isNotEmpty) return firstLine;
    }
    return url?.toString() ?? 'Untitled capture';
  }

  Opportunity copyWith({
    String? status,
    PostAnalysis? analysis,
    String? connectionState,
    Map<String, OutreachDraft>? drafts,
  }) => Opportunity(
    id: id,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
    status: status ?? this.status,
    analysis: analysis ?? this.analysis,
    text: text,
    url: url,
    capturedVia: capturedVia,
    connectionState: connectionState ?? this.connectionState,
    drafts: drafts ?? this.drafts,
  );

  factory Opportunity.fromJson(Map<String, dynamic> json) {
    final analysis = PostAnalysis.fromJson(
      (json['analysis'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final urlValue = json['url'];
    final rawDrafts = json['drafts'];
    final drafts = rawDrafts is Map
        ? rawDrafts.map(
            (key, value) => MapEntry(
              key.toString(),
              OutreachDraft.fromJson((value as Map).cast<String, dynamic>()),
            ),
          )
        : <String, OutreachDraft>{};
    return Opportunity(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      status: json['status'] as String,
      analysis: analysis,
      text: json['text'] as String?,
      url: urlValue is String && urlValue.isNotEmpty
          ? Uri.tryParse(urlValue)
          : null,
      capturedVia: json['capturedVia'] as String? ?? 'manual',
      connectionState: json['connectionState'] as String? ?? 'none',
      drafts: Map.unmodifiable(drafts),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status,
    'analysis': analysis.toJson(),
    'text': text,
    'url': url?.toString(),
    'capturedVia': capturedVia,
    'connectionState': connectionState,
    'drafts': drafts.map((key, value) => MapEntry(key, value.toJson())),
  };

  /// For tests and previews; a CapturedPost is raw input, not an Opportunity.
  static Opportunity fromCaptured(
    CapturedPost post,
    PostAnalysis analysis, {
    required String id,
    String capturedVia = 'manual',
  }) {
    final now = DateTime.now().toUtc();
    return Opportunity(
      id: id,
      createdAt: now,
      updatedAt: now,
      status: 'new',
      analysis: analysis,
      text: post.text,
      url: post.url,
      capturedVia: capturedVia,
    );
  }
}
