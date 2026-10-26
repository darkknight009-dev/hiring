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
    if (!_profile.hasContent) {
      throw const AiAnalysisException(
        'Add your name and headline in Settings → Your profile so drafts are personal.',
      );
    }
    if (!opportunity.isHiring) {
      throw const AiAnalysisException(
        'Outreach is available only for hiring opportunities.',
      );
    }
    final postText = opportunity.text?.trim() ?? '';
    if (postText.isEmpty) {
      throw const AiAnalysisException(
        'The original post text is missing, so a grounded draft cannot be written.',
      );
    }
    final draft = await _deps.ai.generateDraft(
      kind: kind,
      postText: postText,
      posterName: opportunity.posterName,
      role: opportunity.analysis.role,
      company: opportunity.analysis.company,
      profile: _profile,
    );
    _validateDraft(draft);
    final updated = opportunity.copyWith(
      drafts: {...opportunity.drafts, kind: draft},
    );
    await _deps.repository.save(updated);
    _deps.dataChanged();
    return draft;
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

  Future<void> cancelReminder(Opportunity opportunity) async {
    if (kIsWeb) return;
    await AndroidBridge.cancelReminder(_reminderKey(opportunity));
  }

  Future<void> syncReminders() async {
    if (kIsWeb) return;
    final all = await _deps.repository.loadAll();
    for (final opportunity in all) {
      if (opportunity.connectionState == 'requested') {
        await _scheduleReminders(opportunity);
      } else {
        await cancelReminder(opportunity);
      }
    }
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

  void _validateDraft(OutreachDraft draft) {
    final limit = switch (draft.kind) {
      'connectionNote' => 200,
      'dm' => 500,
      _ => null,
    };
    if (limit != null && draft.body.length > limit) {
      throw AiAnalysisException(
        'The AI draft exceeded the ${limit}-character limit. Try again.',
      );
    }
    if (draft.kind == 'email' &&
        draft.subject != null &&
        draft.subject!.length > 70) {
      throw const AiAnalysisException(
        'The AI email subject exceeded the 70-character limit. Try again.',
      );
    }
  }
}
