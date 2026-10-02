import 'package:flutter/material.dart';

import '../../models/captured_post.dart';
import '../../services/capture/capture_provider.dart';
import '../../services/capture/web_capture_provider.dart';
import '../../widgets/page_content.dart';
import '../../widgets/surface_card.dart';

class AnalyzePage extends StatefulWidget {
  const AnalyzePage({super.key, this.captureProvider});

  /// Injectable so future platform adapters feed the same input flow.
  final CaptureProvider? captureProvider;

  @override
  State<AnalyzePage> createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<AnalyzePage> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _text = TextEditingController();
  late final CaptureProvider _captureProvider;
  CapturedPost? _preview;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _captureProvider =
        widget.captureProvider ??
        WebCaptureProvider(
          readDraft: () =>
              CapturedPost.fromInput(text: _text.text, url: _url.text),
        );
  }

  @override
  void dispose() {
    _url.dispose();
    _text.dispose();
    super.dispose();
  }

  void _invalidatePreview(String _) {
    if (_preview != null || _error != null) {
      setState(() {
        _preview = null;
        _error = null;
      });
    }
  }

  Future<void> _capture() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _capturing = true;
      _error = null;
      _preview = null;
    });
    try {
      final captured = await _captureProvider.capturePost();
      if (!mounted) return;
      setState(() => _preview = captured);
      if (captured != null) FocusManager.instance.primaryFocus?.unfocus();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not capture this post. Your input is still here; please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PageContent(
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
            text: 'Capture preview only. AI analysis is not connected yet. Nothing is uploaded, researched, or saved to an opportunity database.',
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Form(
              key: _formKey,
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
                    enabled: !_capturing,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: CapturedPost.validateUrl,
                    onChanged: _invalidatePreview,
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
                    enabled: !_capturing,
                    keyboardType: TextInputType.multiline,
                    minLines: 7,
                    maxLines: 14,
                    maxLength: CapturedPost.maxTextLength,
                    validator: CapturedPost.validateText,
                    onChanged: _invalidatePreview,
                    decoration: const InputDecoration(
                      labelText: 'Post Content',
                      alignLabelWithHint: true,
                      hintText: 'Paste the original post here.\n\nInclude the role, company, application instructions, and poster details if they appear in the post.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Notice(
                    text: 'LinkedIn links are not fetched in this preview. Paste the text to include the post content. Only share information you are permitted to use.',
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
                  FilledButton.icon(
                    onPressed: _capturing ? null : _capture,
                    icon: _capturing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.article_outlined, size: 20),
                    label: Text(
                      _capturing ? 'Capturing input…' : 'Preview capture',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_preview case final post?) ...[
            const SizedBox(height: 24),
            SurfaceCard(
              key: const Key('capture-preview'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Capture preview · not analyzed',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (post.url != null) ...[
                    const SectionLabel('Source URL'),
                    const SizedBox(height: 6),
                    SelectableText(post.url.toString()),
                    const SizedBox(height: 16),
                  ],
                  if (post.text != null) ...[
                    const SectionLabel('Original post'),
                    const SizedBox(height: 6),
                    SelectableText(post.text!),
                    const SizedBox(height: 16),
                  ] else ...[
                    const Notice(
                      text: 'We haven’t retrieved this URL. Please paste the post text before analysis can be added.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Notice(
                    icon: Icons.lock_outline_rounded,
                    text: 'This is an in-memory preview, not a saved opportunity. Refreshing or closing the tab clears it. No hiring decision has been made.',
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Notice(
            icon: Icons.touch_app_outlined,
            text: 'Hiring Radar prepares you to act. It never applies, connects, emails, or messages for you.',
          ),
        ],
      ),
    );
  }
}
