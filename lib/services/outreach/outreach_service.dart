import 'package:flutter/foundation.dart' show kIsWeb;

import '../../app_dependencies.dart';
import '../../models/opportunity_entity.dart';
import '../../models/outreach.dart';
import '../analysis/ai_provider.dart';
import '../platform/android_bridge.dart';
import '../resume/resume_store.dart';

/// Prepares ready-made outreach material. Every send is manual: the user
/// copies the draft or opens their own email/LinkedIn compose. The app only
/// tracks connection state and schedules reminder notifications.
class OutreachService {
  OutreachService(this._deps, {ResumeStore? resumeStore})
    : resume = resumeStore ?? ResumeStore(_deps.settings);

  final AppDependencies _deps;
  final ResumeStore resume;

  UserProfile get _profile => UserProfile(
    name: _deps.settings.profileName,
    headline: _deps.settings.profileHeadline,
    skills: _deps.settings.profileSkills,
    tone: _deps.settings.profileTone,
  );

  bool get hasProfile => _profile.hasContent;

  Future<OutreachDraft> generate({
    required Opportunity opportunity,
    required String kind,
  }) async {
    final ai = _deps.ai;
    if (ai == null) {
      throw const AiAnalysisException(
        'No AI key configured. Add your Gemini API key in Settings first.',
      );
    }
    if (!_profile.hasContent) {
      throw const AiAnalysisException(
        'Add your name and headline in Settings → Your profile so drafts are personal.',
      );
    }
    final draft = await ai.generateDraft(
      kind: kind,
      postText: opportunity.text ?? opportunity.analysis.summary ?? '',
      posterName: _guessPoster(opportunity),
      role: opportunity.analysis.role,
      company: opportunity.analysis.company,
      profile: _profile,
    );
    final updated = opportunity.copyWith(
      drafts: {...opportunity.drafts, kind: draft},
    );
    await _deps.repository.save(updated);
    _deps.dataChanged();
    return draft;
  }

  String? _guessPoster(Opportunity opportunity) {
    // The poster is unknown for radar/share captures unless the AI found a
    // contact; drafts then fall back to a neutral greeting.
    return null;
  }

  /// Marks the invitation as sent and starts interval reminders.
  Future<void> markRequested(Opportunity opportunity) async {
    final updated = opportunity.copyWith(connectionState: 'requested');
    await _deps.repository.save(updated);
    _deps.dataChanged();
    await _scheduleReminders(updated);
  }

  /// Marks the connection as accepted and stops the reminders.
  Future<void> markAccepted(Opportunity opportunity) async {
    final updated = opportunity.copyWith(connectionState: 'accepted');
    await _deps.repository.save(updated);
    _deps.dataChanged();
    await AndroidBridge.cancelReminder(_reminderKey(updated));
  }

  Future<void> _scheduleReminders(Opportunity opportunity) async {
    if (kIsWeb) return;
    final hours = _deps.settings.reminderHours;
    await AndroidBridge.scheduleReminder(
      key: _reminderKey(opportunity),
      title: 'Check your connection request',
      body:
          '${opportunity.displayTitle} — if they accepted, your personalized message is ready to copy.',
      interval: Duration(hours: hours),
    );
  }

  String _reminderKey(Opportunity opportunity) => 'followup-${opportunity.id}';
}
