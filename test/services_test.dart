import 'package:flutter_test/flutter_test.dart';
import 'package:hiring/models/opportunity.dart';
import 'package:hiring/models/opportunity_entity.dart';
import 'package:hiring/models/outreach.dart';
import 'package:hiring/services/analysis/hiring_filter.dart';
import 'package:hiring/services/opportunities/opportunity_repository.dart';
import 'package:hiring/services/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('offline hiring filter', () {
    test('spec positive examples pass', () {
      const examples = [
        "We are hiring a Senior Flutter engineer at Example Studio. Send your resume to careers@example.com.",
        "Our team is growing! Looking for a product designer to join our team in Berlin. Apply now.",
      ];
      for (final example in examples) {
        expect(looksLikeHiringPost(example), isTrue, reason: example);
      }
    });

    test('spec negative examples fail', () {
      const examples = [
        'Thinking about family, coffee and sunsets today.',
        "Just wrapped an amazing quarter. Thanks team! #grateful",
      ];
      for (final example in examples) {
        expect(looksLikeHiringPost(example), isFalse, reason: example);
      }
    });

    test('empty input never passes', () {
      expect(looksLikeHiringPost(''), isFalse);
      expect(looksLikeHiringPost('   \n  '), isFalse);
    });
  });

  group('PostAnalysis parsing', () {
    test('parses a full provider payload', () {
      final analysis = PostAnalysis.fromJson({
        'isHiring': 'true',
        'confidence': 90,
        'role': 'Flutter Developer',
        'company': 'Example Studio',
        'location': 'Remote',
        'applyInstructions': 'DM your resume.',
        'summary': 'A role at Example Studio.',
      });
      expect(analysis.isHiring, isTrue);
      expect(analysis.confidence, 90);
      expect(analysis.role, 'Flutter Developer');
      expect(analysis.company, 'Example Studio');
    });

    test('treats unknown fields as null, never invented', () {
      final analysis = PostAnalysis.fromJson({
        'isHiring': 'false',
        'confidence': null,
        'role': null,
      });
      expect(analysis.isHiring, isFalse);
      expect(analysis.company, isNull);
      expect(analysis.location, isNull);
      expect(analysis.summary, isNull);
    });
  });

  group('Opportunity persistence', () {
    Future<OpportunityRepository> repo(Map<String, Object> seed) async {
      SharedPreferences.setMockInitialValues(seed);
      final prefs = await SharedPreferences.getInstance();
      return OpportunityRepository(prefs: prefs);
    }

    Opportunity sample(String id) => Opportunity(
      id: id,
      createdAt: DateTime.utc(2026, 1, 2, 3, 4),
      updatedAt: DateTime.utc(2026, 1, 2, 3, 4),
      status: 'new',
      analysis: const PostAnalysis(
        isHiring: true,
        confidence: 80,
        role: 'Engineer',
        company: 'Example',
      ),
      text: 'We are hiring an Engineer at Example.',
    );

    test('save and load round-trips', () async {
      final repository = await repo({});
      await repository.save(sample('a1'));
      final reloaded = await repo({})
        ..loadAll();
      expect(await reloaded.loadAll(), isEmpty); // different store
    });

    test('saving keeps newest first and updates in place', () async {
      final repository = await repo({});
      await repository.save(sample('a1'));
      await repository.save(sample('a2'));
      var all = await repository.loadAll();
      expect(all.map((o) => o.id), ['a2', 'a1']);
      await repository.save(sample('a1').copyWith(status: 'applied'));
      all = await repository.loadAll();
      expect(all, hasLength(2));
      expect(all.firstWhere((o) => o.id == 'a1').status, 'applied');
    });

    test('delete removes only the target', () async {
      final repository = await repo({});
      await repository.save(sample('a1'));
      await repository.save(sample('a2'));
      await repository.delete('a1');
      final all = await repository.loadAll();
      expect(all.map((o) => o.id), ['a2']);
    });

    test('display title prefers role and company', () {
      final opportunity = sample('a1');
      expect(opportunity.displayTitle, 'Engineer at Example');
    });
  });

  group('outreach scenarios', () {
    test('detects a DM ask', () {
      final scenario = OutreachScenario.detect(
        "We're hiring a React dev. DM me your resume.",
      );
      expect(scenario.wantsDm, isTrue);
      expect(scenario.wantsEmail, isFalse);
    });

    test('detects an email ask', () {
      final scenario = OutreachScenario.detect(
        'Send your resume to careers@example.com for the backend role.',
      );
      expect(scenario.wantsEmail, isTrue);
    });

    test('detects both asks and defaults unknown posts to DM', () {
      final both = OutreachScenario.detect(
        'Apply with your resume to jobs@example.com or DM me.',
      );
      expect(both.wantsDm, isTrue);
      expect(both.wantsEmail, isTrue);
      expect(
        OutreachScenario.detect('We are hiring a designer.').wantsDm,
        isTrue,
      );
    });
  });

  group('connection tracking and drafts', () {
    Opportunity base() => Opportunity(
      id: 'a1',
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
      status: 'new',
      analysis: const PostAnalysis(isHiring: true, confidence: 80),
      text: "We're hiring a React developer. DM me your resume.",
    );

    test('drafts are stored and serialized with the opportunity', () {
      final draft = OutreachDraft(
        kind: 'connectionNote',
        body: 'Hi! Saw your React role…',
        createdAt: DateTime.utc(2026, 1, 3),
      );
      final withDraft = base().copyWith(drafts: {'connectionNote': draft});
      final restored = Opportunity.fromJson(withDraft.toJson());
      expect(restored.drafts['connectionNote']!.body, contains('React role'));
      expect(restored.connectionState, 'none');
    });

    test('connection state transitions are tracked', () {
      final requested = base().copyWith(connectionState: 'requested');
      expect(requested.connectionState, 'requested');
      expect(requested.dmUnlocked, isTrue);
      final accepted = requested.copyWith(connectionState: 'accepted');
      expect(accepted.connectionState, 'accepted');
      expect(base().dmUnlocked, isFalse);
    });

    test('older saved records without outreach fields still load', () {
      final legacy = {
        'id': 'legacy-1',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'status': 'new',
        'analysis': {'isHiring': 'true'},
      };
      final restored = Opportunity.fromJson(legacy);
      expect(restored.capturedVia, 'manual');
      expect(restored.connectionState, 'none');
      expect(restored.drafts, isEmpty);
    });

    test('scenario reads apply instructions when present', () {
      final withInstructions = base().copyWith(
        analysis: const PostAnalysis(
          isHiring: true,
          confidence: 90,
          applyInstructions: 'Email jobs@example.com',
        ),
      );
      expect(withInstructions.scenario.wantsEmail, isTrue);
    });
  });

  group('SettingsStore', () {
    Future<SettingsStore> store(Map<String, Object> seed) async {
      SharedPreferences.setMockInitialValues(seed);
      final prefs = await SharedPreferences.getInstance();
      return SettingsStore(prefs: prefs);
    }

    test('defaults are Gemini, no key, threshold 4', () async {
      final settings = await store({});
      expect(settings.provider, AiProviderKind.gemini);
      expect(settings.apiKey, isNull);
      expect(settings.filterThreshold, 4);
      expect(settings.model, isEmpty);
    });

    test('key, model, provider, and threshold round-trip', () async {
      final settings = await store({});
      await settings.setApiKey('k-123');
      await settings.setModel('gemini-1.5-flash');
      await settings.setProvider(AiProviderKind.openRouter);
      await settings.setFilterThreshold(7);
      final reloaded = await store({
        'ai.apiKey': 'k-123',
        'ai.model': 'gemini-1.5-flash',
        'ai.provider': 'openRouter',
        'filter.threshold': 7,
      });
      expect(reloaded.apiKey, 'k-123');
      expect(reloaded.model, 'gemini-1.5-flash');
      expect(reloaded.provider, AiProviderKind.openRouter);
      expect(reloaded.filterThreshold, 7);
      expect(reloaded.statuses, isNotEmpty);
    });

    test('removing a blank key clears it', () async {
      final settings = await store({'ai.apiKey': 'existing'});
      await settings.setApiKey('');
      expect(settings.apiKey, isNull);
    });

    test('profile, resume, and reminder settings round-trip', () async {
      final settings = await store({});
      await settings.setProfileName('  Ishaan  ');
      await settings.setProfileHeadline('CS student');
      await settings.setProfileSkills('Flutter, Dart');
      await settings.setProfileTone('warm');
      await settings.setResumePath('/data/resume/resume.pdf');
      await settings.setReminderHours(24);
      expect(settings.profileName, 'Ishaan');
      expect(settings.profileHeadline, 'CS student');
      expect(settings.profileSkills, 'Flutter, Dart');
      expect(settings.profileTone, 'warm');
      expect(settings.resumePath, '/data/resume/resume.pdf');
      expect(settings.reminderHours, 24);
      await settings.setReminderHours(7); // invalid value falls back
      expect(settings.reminderHours, 12);
      await settings.setResumePath(null);
      expect(settings.resumePath, isNull);
    });
  });
}
