# FeedRadar

**Your feed has hiring posts. Your radar catches them.** A personal opportunity radar with a background scanner for Android: while you scroll LinkedIn, hiring posts matching *your* job preferences are detected locally, analyzed with your own AI key (Gemini or NVIDIA), and turned into ready-made outreach material — a connection note, a personalized DM, or an email draft. **You send everything yourself. The app never clicks, types, or sends anything.**

> **Current milestone: onboarding + preference-tuned radar (0.4).** First-launch onboarding (name, headline, job preferences) that syncs directly into the radar's capture filter, an animated radar loader and page transitions, NVIDIA NIM as a second AI provider, and everything from 0.3: Android background capture (read-only accessibility), connection tracking with interval reminders, AI-drafted outreach, resume attachment, and the local-only inbox. No backend, no automation of any LinkedIn action.

> ⚠️ **Honest risk note:** observing another app's content via an Accessibility Service is automation-adjacent and outside LinkedIn's terms of service. The radar is strictly read-only, keeps all data on-device, and never interacts with LinkedIn — but using it is your decision and account restriction is a possible consequence. Enable it in Accessibility settings; disable it any time.

## What works now

- **Onboarding (first launch):** a three-step flow — welcome, your name/headline, and job preferences (roles/keywords + optional locations). Preferences are saved to settings and pushed into the radar, so only matching posts are captured. Everything is editable later in Settings.
- Responsive overview with a desktop sidebar and compact mobile bottom navigation, light/dark themes, **animated page transitions**, and an **animated radar loader** during AI work.
- Manual capture (URL/text/share target) with validation, plus **background radar capture** on Android.
- **Offline hiring filter**: cheap rule-based detection gates AI calls so obvious non-posts never cost quota.
- **AI analysis** (Google Gemini **or NVIDIA NIM**, free tiers): structured extraction of role, company, location, apply instructions, summary, and a hiring verdict with confidence — nullable fields, never invented values.
- **Saved opportunities** with statuses (New, Need action, Applied, Follow-up, Archived), search, and filtering — all stored **locally on your device**.
- **Ready-made outreach, sent by you:**
  - *DM posts* → the app asks whether you are connected. Not connected: it crafts a ≤200-char connection note, then (after you mark "I sent the request") repeats reminders until you mark "they accepted", which unlocks the personalized DM draft. Already connected: straight to the DM draft.
  - *Email posts* → it crafts a subject + body and can open your email app with everything pre-filled and your stored resume PDF attached.
  - Every draft is copyable and regenerable; the AI may only use facts from your profile card and the post itself.
- **Background radar (Android):** a read-only Accessibility Service observes visible LinkedIn text while you scroll, gates it with the offline filter **and your job preferences**, analyzes, saves, and sends a local notification. No clicks, no typing, no sends, no data leaving the device.
- **Capture state stays in sync both ways:** stopping or resuming from the notification shade updates the app the moment you return to it, and stopping or resuming in the app updates the shade. The status card, Settings, and the ongoing notification always agree — including after you grant or revoke accessibility in system settings.
- Settings: filter threshold, reminder interval, job preferences (synced with the radar), profile card (name/headline/skills/tone), resume PDF. AI itself is built in — no provider or key to manage.
- Branded web manifest, maskable icons, favicon, and matching Android launcher icons.

**Not yet implemented:** auto-sending (deliberately), company research, backend sync, authentication, and the full offline/install PWA milestone. AI runs directly from the device to the provider; there is no server in the middle.

## Stack and architecture

| Layer | Choice | State |
| --- | --- | --- |
| Shared UI and app logic | Flutter / Dart | Implemented |
| Persistence | `shared_preferences` (local-only JSON) | Implemented |
| AI | `AiProvider` abstraction; Gemini + NVIDIA NIM implementations | Implemented; key user-supplied |
| Hiring filter | Offline rule-based scoring | Implemented |
| Background capture | Android Accessibility Service (read-only) | Implemented; sideload APK |
| Outreach | Draft generation + copy/email handoff | Implemented; sends are manual |
| REST backend | FastAPI + PostgreSQL | Planned |
| Public research | Server-side `ResearchProvider` abstraction | Planned |

Flows:

```text
PWA:  capture (manual or share target) → offline filter → AI extraction → saved opportunity
APK:  scroll LinkedIn → radar observes → offline filter → AI → save + notification
then: connection question → drafts (note / DM / email) → reminders → USER SENDS EVERYTHING
```

## Project structure

```text
lib/
  main.dart                         # Entry point; loads settings, share intake
  app.dart                          # App-wide theme state
  app_dependencies.dart             # Dependency scope (settings, repo, AI factory)
  core/
    routing/app_destination.dart    # Overview, Opportunities, Analyze, Settings
    theme/app_theme.dart            # Colors, typography, spacing, control styles
  features/
    dashboard/dashboard_page.dart   # Live counts and recent opportunities
    analyze/analyze_page.dart       # Capture → filter → AI → save
    onboarding/onboarding_page.dart # First launch: name + job preferences
    opportunities/opportunities_page.dart  # Inbox list, detail, statuses
    settings/settings_page.dart     # Provider, API key, preferences, data controls
  models/
    captured_post.dart              # Validated raw input
    opportunity.dart                # PostAnalysis (AI result)
    opportunity_entity.dart         # Saved opportunity: status, connection, drafts
    outreach.dart                   # OutreachDraft + DM/email scenario detection
  services/
    analysis/
      hiring_filter.dart            # Offline gating filter
      ai_provider.dart              # Contract + result/error types
      gemini_ai_provider.dart       # HTTPS call, JSON mode, mapped errors
      nvidia_ai_provider.dart       # NVIDIA NIM (OpenAI-compatible) implementation
    capture/                        # Manual capture contract + web impl
    opportunities/opportunity_repository.dart  # Local JSON persistence
    outreach/outreach_service.dart  # Draft generation + reminders
    platform/android_bridge.dart    # One channel: shares, radar, notifications, email
    radar/radar_capture.dart        # Radar pipeline: filter → analyze → save → notify
    resume/resume_store.dart        # Private PDF storage
    settings/settings_store.dart    # Provider/key/model/threshold/profile/reminders
    share/                          # Share target: parser + web/IO impls
  widgets/                          # Shell (animated transitions), radar loader,
                                    # keyword chip field, cards, notices, logo
web/                                # Manifest (+ share_target), icons
android/
  RadarAccessibilityService.kt      # Read-only LinkedIn feed scanner
  MainActivity.kt                   # Shares, radar bridge, notifications, reminders, email
  ReminderReceiver.kt               # Interval follow-up reminders
  res/xml/                          # Accessibility + FileProvider config
tool/generate_icons.py              # Regenerates web + Android icons
test/                               # 39 unit and widget tests
```

## Local setup

Run all commands from this directory. Developed with **Flutter 3.47.6** and **Dart 3.13.5** (`sdk: ^3.13.5`).

```bash
flutter --version
flutter pub get
```

### Run the PWA in Brave (no Chrome needed)

```bash
CHROME_EXECUTABLE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  flutter run -d chrome --web-hostname 127.0.0.1 --web-port 8080
```

Or serve the release build:

```bash
flutter build web --no-web-resources-cdn
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8080` in Brave. Press `q` in the Flutter terminal to stop a dev run.

### AI analysis (built in)

AI is built in — no API key to create or paste. Post analysis and outreach drafts run on NVIDIA NIM models (`nvidia/nemotron-3-super-120b-a12b` by default) with a key embedded in the app.

1. Fill **Your profile** (name, headline, skills, tone) — drafts use only these facts.
2. Optionally pick your **resume PDF** for email attachments.
3. Set **Job preferences** — the radar then captures only posts mentioning your roles (and locations, if set).

Note: an embedded key is extractable by anyone who has the APK; rotate it at build.nvidia.com if it is ever abused. Posts that the offline filter scores below the threshold skip AI entirely.

### Enable the background radar (Android)

1. Open **Settings → Background radar → Accessibility settings** and enable **FeedRadar** for the LinkedIn app.
2. Allow notifications so captures and follow-up reminders appear.
3. Scroll your feed. Hiring posts land in **Opportunities** with a "by radar" badge.
4. Open an opportunity and follow the outreach path: connection note → reminders → personalized message, or the email draft with resume attached.

### Try the analyzed inbox

1. Select **Analyze post** and paste a hiring post, e.g. `We're hiring a React developer at Example Studio. DM me your resume.`
2. Select **Analyze post**. With a key configured you get a verdict and extracted fields; without one, the capture is saved without analysis.
3. Select **Save to my inbox**, then check **Overview** counts and the **Opportunities** list.
4. Change a status from the detail sheet, search, and delete.
5. Share text into the app from another app (Android) to land on the capture screen.

### Build the Android app

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Install on a device: transfer the APK and open it (enable "install unknown apps" for your file manager), or connect a device and run `flutter install`. The release build is debug-signed for personal use; production signing is deferred.

### Testing

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

66 tests cover: capture validation boundaries and hostile URLs (including lnkd.in short-link acceptance and look-alike host rejection); the offline filter on the four spec examples; analysis parsing with unknowns-as-null; DM/email scenario detection; connection-state transitions and draft serialization (including legacy records); repository round-trip and status updates; settings persistence including profile/resume/reminders and job-preference gating; the NVIDIA provider contract (payload, rejected key, fenced JSON) plus the reasoning-token cap in the request, an exhausted output budget, a non-string draft body, and prose returned instead of JSON; poster-name forwarding into drafts; the full onboarding flow including preference persistence; the dashboard radar status card (ON state, capture count, enable CTA); a capture toggle made outside the app (notification shade) reaching the dashboard; mid-session share delivery into the capture form; responsive layouts at 320/390/768/1440 px; 200% text scaling; theme toggling; save/count flows; AI-missing honesty; and recoverable capture failures.

The accessibility service, notifications, and alarms are exercised on-device only; keep that in mind when testing on a real phone.

## Roadmap

1. ✅ Environment, design system, responsive shell, validated manual capture.
2. ✅ Domain models, local opportunity inbox with statuses, offline filter.
3. ✅ Device-side AI extraction via user-supplied Gemini key; PWA share target; Android APK with share-sheet intake.
4. ✅ Onboarding with job preferences synced into the radar, NVIDIA provider, animated transitions and loader, FeedRadar rebrand.
5. Permitted company/public-professional research with source evidence.
6. FastAPI/PostgreSQL backend with auth and sync (opt-in; local-first remains).
7. Complete PWA offline/install/update behavior.
8. Android polish: production identity/signing, capture-layer design.

## Known limitations

- **The radar is not perfect:** it reads visible text heuristically, so it can miss posts, capture fragments, or guess the author's name. Treat captures as candidates and verify in the inbox. It only works while the LinkedIn app is on screen and the Flutter app process is alive.
- **Everything is stored on one device;** clearing browser/app data deletes your inbox. Export/backup is not built yet.
- AI output depends on the provider; the app shows failures honestly and never fabricates fields.
- The offline filter is intentionally conservative; some hiring posts may skip AI (lower the threshold in Settings). Job preferences are strict by design: a post must mention your roles (and locations, if set) or it is skipped.
- With job preferences set, the radar relies on keyword matching; posts phrased without any of your keywords are not captured.
- LinkedIn limits connection notes to 200 characters; the app shows a live counter but the final paste is on you.
- AI runs on the built-in NVIDIA key only: Settings exposes no provider, key, or model override, so an exhausted or revoked key can only be fixed by shipping a new build. `GeminiAiProvider` still exists but is never constructed, and the OpenRouter entry in the settings store is vestigial.
- Shell navigation has no deep links/browser-history integration yet.
- Only public professional information is eligible for future research; no fabricated contacts, bypassing access controls, or private-data collection.
