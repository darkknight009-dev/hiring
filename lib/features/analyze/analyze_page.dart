import 'package:flutter/material.dart';

import '../../app_dependencies.dart';
import '../../models/captured_post.dart';
import '../../models/opportunity.dart';
import '../../models/opportunity_entity.dart';
import '../../services/analysis/ai_provider.dart';
import '../../services/capture/capture_provider.dart';
import '../../services/capture/web_capture_provider.dart';
import '../../services/analysis/hiring_filter.dart';
import '../../widgets/page_content.dart';
import '../../widgets/surface_card.dart';

/// Capture → cheap filter → AI analysis → save. The AI step is skipped only
/// when the offline filter is sure the post is not hiring.
class AnalyzePage extends StatefulWidget {
  const AnalyzePage({super.key, required this.deps, this.captureProvider});

  final AppDependencies deps;

  /// Injectable so tests and future platform adapters feed the same flow.
  final CaptureProvider? captureProvider;

  @override
  State<AnalyzePage> createState() => _AnalyzePageState();
}

enum _Stage { idle, capturing, analyzing, done }

class _AnalyzePageState extends State<AnalyzePage> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _text = TextEditingController();
  CapturedPost? _captured;
  PostAnalysis? _analysis;
  String? _analysisNote;
  String? _error;
  _Stage _stage = _Stage.idle;

  @override
  void initState() {
    super.initState();
    final pending = widget.deps.takePendingCapture();
    if (pending != null) {
      _text.text = pending.text ?? '';
      _url.text = pending.url?.toString() ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _capture();
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _text.dispose();
    super.dispose();
  }

  void _invalidate(String _) {
    if (_captured != null || _error != null) {
      setState(() {
        _captured = null;
        _analysis = null;
        _analysisNote = null;
        _error = null;
        _stage = _Stage.idle;
      });
    }
  }

  Future<void> _capture() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _stage = _Stage.capturing;
      _error = null;
      _analysis = null;
      _analysisNote = null;
    });
    try {
      final provider =
          widget.captureProvider ??
          WebCaptureProvider(
            readDraft: () =>
                CapturedPost.fromInput(text: _text.text, url: _url.text),
          );
      final captured = await provider.capturePost();
      if (!mounted) return;
      if (captured == null) {
        setState(() => _stage = _Stage.idle);
        return;
      }
      setState(() {
        _captured = captured;
        _stage = _Stage.idle;
      });
      FocusManager.instance.primaryFocus?.unfocus();
      await _runAnalysis(captured);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _stage = _Stage.idle;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not capture this post. Your input is still here; please try again.';
          _stage = _Stage.idle;
        });
      }
    }
  }

  Future<void> _runAnalysis(CapturedPost captured) async {
    final postText = captured.text ?? '';
    final deps = widget.deps;

    // Offline gate: skip AI spend on obvious non-hiring posts.
    if (postText.isNotEmpty && !looksLikeHiringPost(postText)) {
      setState(() {
        _captured = captured;
        _analysis = null;
        _analysisNote = 'The offline filter found no hiring signals, so no AI analysis was run. You can still save or edit the capture.';
        _stage = _Stage.done;
      });
      return;
    }

    final ai = deps.ai;
    if (ai == null) {
      setState(() {
        _captured = captured;
        _analysis = null;
        _analysisNote = postText.isEmpty
            ? 'Add the post text so the offline filter and AI can read it.'
            : 'No AI key configured. Open Settings to add your Gemini API key, then analyze again.';
        _stage = _Stage.done;
      });
      return;
    }

    setState(() => _stage = _Stage.analyzing);
    try {
      final result = await ai.analyzePost(text: postText, url: captured.url);
      if (!mounted) return;
      setState(() {
        _captured = captured;
        _analysis = result.analysis;
        _analysisNote = 'Analyzed with ${result.modelUsed}.';
        _stage = _Stage.done;
      });
    } on AiAnalysisException catch (error) {
      if (!mounted) return;
      setState(() {
        _captured = captured;
        _analysis = null;
        _error = error.message;
        _stage = _Stage.done;
      });
    }
  }

  Future<void> _save() async {
    final captured = _captured;
    if (captured == null) return;
    final analysis =
        _analysis ??
        PostAnalysis(
          isHiring: false,
          confidence: null,
          summary: 'Saved without analysis.',
        );
    final opportunity = Opportunity.fromCaptured(
      captured,
      analysis,
      id: DateTime.now().microsecondsSinceEpoch.toString(),
    );
    await widget.deps.repository.save(opportunity);
    if (!mounted) return;
    setState(() {
      _captured = null;
      _analysis = null;
      _analysisNote = null;
      _text.clear();
      _url.clear();
      _stage = _Stage.idle;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opportunity saved on this device.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _stage == _Stage.capturing || _stage == _Stage.analyzing;

    return PageContent(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Start with a post'),
            const SizedBox(height: 14),
            Text(
              'Analyze LinkedIn Opportunity',
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Found something promising? Bring it here before it gets lost in your feed.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            const Notice(
              text: 'Captured posts stay on this device. AI analysis uses your own provider key and receives only the post you paste.',
            ),
            const SizedBox(height: 20),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('The original post', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Add a URL, post text, or both.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('post-url'),
                    controller: _url,
                    enabled: !busy,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: CapturedPost.validateUrl,
                    onChanged: _invalidate,
                    maxLength: CapturedPost.maxUrlLength,
                    decoration: const InputDecoration(
                      labelText: 'LinkedIn Post URL',
                      hintText: 'https://www.linkedin.com/posts/…',
                      counterText: '',
                      prefixIcon: Icon(Icons.link_rounded, size: 21),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('post-text'),
                    controller: _text,
                    enabled: !busy,
                    keyboardType: TextInputType.multiline,
                    minLines: 7,
                    maxLines: 14,
                    maxLength: CapturedPost.maxTextLength,
                    validator: CapturedPost.validateText,
                    onChanged: _invalidate,
                    decoration: const InputDecoration(
                      labelText: 'Post Content',
                      alignLabelWithHint: true,
                      hintText: 'Paste the original post here.\n\nInclude the role, company, application instructions, and poster details if they appear in the post.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Notice(
                    text: 'LinkedIn links are not fetched. Paste the post text so the filter and AI can read it. Only share information you are permitted to use.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: busy ? null : _capture,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_outlined, size: 20),
                        label: Text(switch (_stage) {
                          _Stage.capturing => 'Capturing input…',
                          _Stage.analyzing => 'Analyzing with AI…',
                          _Stage.idle || _Stage.done => 'Analyze post',
                        }),
                      ),
                    ],
                  ),
                  if (_captured != null) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    _PreviewSection(
                      captured: _captured!,
                      analysis: _analysis,
                      note: _analysisNote,
                      onSave: _save,
                      canSave: _stage == _Stage.done,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Notice(
              icon: Icons.touch_app_outlined,
              text: 'Hiring Radar prepares you to act. It never applies, connects, emails, or messages for you.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    required this.captured,
    required this.analysis,
    required this.note,
    required this.onSave,
    required this.canSave,
  });

  final CapturedPost captured;
  final PostAnalysis? analysis;
  final String? note;
  final Future<void> Function() onSave;
  final bool canSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            analysis == null
                ? 'Capture preview · not analyzed'
                : 'Analysis result',
            style: theme.textTheme.titleLarge,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (captured.url != null) ...[
          const SectionLabel('Source URL'),
          const SizedBox(height: 6),
          SelectableText(captured.url.toString()),
          const SizedBox(height: 16),
        ],
        if (captured.text != null) ...[
          const SectionLabel('Original post'),
          const SizedBox(height: 6),
          SelectableText(captured.text!),
          const SizedBox(height: 16),
        ],
        if (analysis != null) ...[
          const SectionLabel('Extracted details'),
          const SizedBox(height: 8),
          _AnalysisGrid(analysis: analysis!),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: canSave ? () => onSave() : null,
          icon: const Icon(Icons.save_outlined, size: 20),
          label: const Text('Save to my inbox'),
        ),
        const SizedBox(height: 4),
        const Notice(
          icon: Icons.lock_outline_rounded,
          text: 'Saved on this device only. You choose what happens next; nothing is sent automatically.',
        ),
      ],
    );
  }
}

class _AnalysisGrid extends StatelessWidget {
  const _AnalysisGrid({required this.analysis});

  final PostAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    String? valueOf(String? value) => value;
    final rows = <(String, String)>[
      (
        'Verdict',
        analysis.isHiring ? 'Looks like a hiring post' : 'Not a hiring post',
      ),
      if (analysis.confidence != null)
        ('Confidence', '${analysis.confidence}%'),
      if (valueOf(analysis.role) != null) ('Role', analysis.role!),
      if (valueOf(analysis.company) != null) ('Company', analysis.company!),
      if (valueOf(analysis.location) != null) ('Location', analysis.location!),
      if (valueOf(analysis.applyInstructions) != null)
        ('How to apply', analysis.applyInstructions!),
      if (valueOf(analysis.summary) != null) ('Summary', analysis.summary!),
    ];
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(child: SelectableText(value)),
              ],
            ),
          ),
      ],
    );
  }
}
