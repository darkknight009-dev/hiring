import 'package:flutter/foundation.dart';

/// AI/heuristic analysis of a captured post. All fields are nullable because
/// extraction can miss information; the app never invents values.
@immutable
class PostAnalysis {
  const PostAnalysis({
    required this.isHiring,
    required this.confidence,
    this.role,
    this.company,
    this.location,
    this.applyInstructions,
    this.summary,
    this.posterName,
  });

  factory PostAnalysis.fromJson(Map<String, dynamic> json) {
    int? readInt(Object? value) => value is int ? value : null;
    String? readString(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return PostAnalysis(
      isHiring:
          readString(json['isHiring'])?.toLowerCase() == 'true' ||
          json['isHiring'] == true,
      confidence: readInt(json['confidence']),
      role: readString(json['role']),
      company: readString(json['company']),
      location: readString(json['location']),
      applyInstructions: readString(json['applyInstructions']),
      summary: readString(json['summary']),
      posterName: readString(json['posterName']),
    );
  }

  /// True when the post is a hiring opportunity worth keeping.
  final bool isHiring;

  /// 0–100 extraction confidence, when the provider reports one.
  final int? confidence;
  final String? role;
  final String? company;
  final String? location;
  final String? applyInstructions;
  final String? summary;

  /// Name of the person who posted, when visible in the post text.
  final String? posterName;

  Map<String, dynamic> toJson() => {
    'isHiring': isHiring,
    'confidence': confidence,
    'role': role,
    'company': company,
    'location': location,
    'applyInstructions': applyInstructions,
    'summary': summary,
    'posterName': posterName,
  };
}
