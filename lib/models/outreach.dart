import 'package:flutter/foundation.dart';

/// Ready-made material the app prepares. The user always sends it manually.
@immutable
class OutreachDraft {
  const OutreachDraft({
    required this.kind,
    required this.body,
    this.subject,
    required this.createdAt,
  });

  /// `connectionNote` | `dm` | `email`
  final String kind;
  final String? subject;
  final String body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'subject': subject,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OutreachDraft.fromJson(Map<String, dynamic> json) => OutreachDraft(
    kind: json['kind'] as String,
    subject: json['subject'] as String?,
    body: json['body'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now().toUtc(),
  );
}

/// Whether the post asks for a DM or an email (or both).
@immutable
class OutreachScenario {
  const OutreachScenario({required this.wantsDm, required this.wantsEmail});

  final bool wantsDm;
  final bool wantsEmail;

  bool get isAmbiguous => !wantsDm && !wantsEmail;

  static final _emailSignals = RegExp(
    r'[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|\bemail\b|\be-?mail (?:your|me|us)\b|'
    r'\bmail (?:your|me|us)\b|\bcareers?@|\bsend (?:your|me|us) (?:your )?resume to\b',
    caseSensitive: false,
  );

  static final _dmSignals = RegExp(
    r'\bdm\b|\bdms?\b|\bmessage me\b|\bmsg me\b|\binbox me\b|\bcomment\b|'
    r'\bdrop a (?:comment|message)\b|\binterested\b|\bhit me up\b',
    caseSensitive: false,
  );

  static OutreachScenario detect(String text) {
    final wantsEmail = _emailSignals.hasMatch(text);
    final wantsDm = _dmSignals.hasMatch(text);
    // A DM ask is the default when the post says nothing explicit.
    return OutreachScenario(
      wantsDm: wantsDm || !wantsEmail,
      wantsEmail: wantsEmail,
    );
  }
}
